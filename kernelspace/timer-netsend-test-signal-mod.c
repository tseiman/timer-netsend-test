
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <asm/siginfo.h>
#include <linux/sched.h>
#include <linux/uaccess.h>
#include <linux/fs.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/types.h>
#include <linux/interrupt.h>
#include <linux/hrtimer.h>

#define PROC_ENTRY_FILENAME	"signal_ktest"
#define PROCFS_MAX_SIZE 	512


struct siginfo sinfo;
static pid_t pid;
static unsigned int timer_sec;
static unsigned int timer_nsec;

struct task_struct *task; 
static struct hrtimer htimer;
static ktime_t kt_period;



/**
 * The proc file buffer (512 byte) for this module
 *
 */
static char procfs_buffer[PROCFS_MAX_SIZE];


/* size of data hold in procfs buffer */
static unsigned long procfs_buffer_size = 0;

static enum hrtimer_restart timer_callback(struct hrtimer * timer);

static void start_timer(void) {
    kt_period = ktime_set(timer_sec, timer_nsec); //seconds,nanoseconds
    hrtimer_init (& htimer, CLOCK_REALTIME, HRTIMER_MODE_REL);
    htimer.function = &timer_callback;
    hrtimer_start(& htimer, kt_period, HRTIMER_MODE_REL);

}

static void stop_timer(void) {
    hrtimer_cancel( &htimer );    

}


static enum hrtimer_restart timer_callback(struct hrtimer * timer) {

    if(task != NULL) {
	send_sig_info (SIGIO, &sinfo, task); /* Send signal to user program */ 
    } else {
	printk("Signal handling not correctly initialized\n");
	return HRTIMER_NORESTART;
    }
    
    
    hrtimer_forward_now(timer, kt_period);
    return HRTIMER_RESTART;
}




static void init_signal(void) {

    task = NULL;
    if(pid == 0) {
	printk("PID is 0 = invalid (we don't want to send init any signals)\n");
	return;
    }


    memset(&sinfo, 0, sizeof(struct siginfo));
    sinfo.si_signo = SIGIO;
    sinfo.si_code = SI_USER;
//task = find_task_by_vpid(pid); // I am also working on new and old version of UBUNTU so thats why this is here	
    task = pid_task(find_vpid(pid), PIDTYPE_PID); 
    
    if(task == NULL) {
	printk("Cannot find PID from user program\n");
    }

    printk(KERN_INFO" Task is initialized\n");
    
    start_timer();    

}


/* 
 * ProcFS IO
 * shows configuration on procfile read 
 */
static int st_show(struct seq_file *m, void *v) {
    seq_printf(m, "timer.sec: %u\n", timer_sec);
    seq_printf(m, "timer.nsec: %u\n", timer_nsec);
    seq_printf(m, "process.pid: %d\n", pid);
    return 0;
}

/* 
 * ProcFS IO
 * handler for procfs open
 */
static int st_open(struct inode *inode, struct file *file) {
    return single_open(file, st_show, NULL);
}



/* 
 * Macro only for st_write() function below,
 * which will convert data which is written to ProcFS
 * to int and checks if this is matching given condition
 * converted data will be stored on success in given variable
 * on fail it jumps to error condition
 * it will log activities to kernel log.
 * Paremters:
 * 	POSITIVE_CONDITION	- condition which checks that he given integer is matching expectation
 *	VARIABLE_NAME		- the variable where the data should be stored in
 *	PARAMTER_NAME		- the variable name as string for error or success message
 * 	ERROR_MESSAGE		- error message which is wrtten to kernel log in case data is not matching expectation
 */
#define PROC_TO_INT(POSITIVE_CONDITION, VARIABLE_NAME, PARAMETER_NAME, ERROR_MSG) 		\
        integer_data=simple_strtoul(procfs_value, &stroul_endptr, 0); 				\
        if (integer_data == 0 && stroul_endptr == procfs_buffer) {  				\
	    printk(KERN_WARNING "given value was not a valid integer: %u\n", integer_data); 	\
        } else {										\
	    if(POSITIVE_CONDITION) { 								\
		snprintf(compare_back_buffer,22,"%u",integer_data);				\
		if(strncmp(procfs_value,compare_back_buffer,22)) {				\
		    printk(KERN_WARNING "given value was not a valid integer: %s\n", 		\
			    procfs_value); 							\
		    goto error_write_proc2;							\
		}										\
		VARIABLE_NAME = integer_data;							\
		printk(KERN_INFO "set %s to %u \n", PARAMETER_NAME, VARIABLE_NAME);		\
	    } else { 										\
		ERROR_MSG; 									\
		goto error_write_proc2;								\
	    }											\
	}



/* 
 * ProcFS IO
 * handler for procfs write. it parses different inputs, converts the data and
 * updates varaibles belonging to written parameter
 */
static ssize_t st_write(struct file *file, const char *buffer, size_t len, loff_t * off) {
    char *procfs_parameter;		// pointer of the parameter name is stored here
    char *procfs_value;			// pointer of the value is stored here 
    unsigned int integer_data;		// temporary vaiable to store converted integer
    char *stroul_endptr;		// on string to int conversion, to check if conversion was OK
    char compare_back_buffer[64];	// used to see if converted data matches to that one written 
					// (is that not the case, written data doesn't match expected format)

    // copy data from userspace to kernel space
    
    if ( len > PROCFS_MAX_SIZE ) {
	procfs_buffer_size = PROCFS_MAX_SIZE;
    } else {
	procfs_buffer_size = len;
    }
    
    if ( copy_from_user(procfs_buffer, buffer, procfs_buffer_size) ) {
	goto error_write_proc;
    }

    printk(KERN_DEBUG "read string from proc: %s \n", procfs_buffer);
    
    
    // tokenize input given e.g. as "ethernet.dev=eth1" to procfs_parameter-->"ethernet.dev" and procfs_value-->"eth1"
    // and check if input was in required format (PARAMETER=VALUE), is this is not the case go to error condition
     
    procfs_value = strchr(procfs_buffer, '\n');
    if(procfs_value != NULL) {
	*procfs_value = '\0';
    } else {
    	goto error_write_proc;
    }

    procfs_value = strchr(procfs_buffer, '=') + 1;
    if(procfs_value == NULL) {
	goto error_write_proc;
    }
        
    procfs_parameter = strchr(procfs_buffer, '=');
    if(procfs_parameter != NULL) {
	*procfs_parameter = '\0';
    } else {
    	goto error_write_proc;
    }
    
    procfs_parameter = procfs_buffer;

    if(procfs_parameter == NULL) {
	goto error_write_proc;
    }
        
    if(strnlen(procfs_parameter,PROCFS_MAX_SIZE) == 0 || strnlen(procfs_value,PROCFS_MAX_SIZE) == 0) {
	goto error_write_proc;
    }

    // reaching here the parameter was in the format PARAMETER=VALUE

    printk(KERN_INFO "got new proc input %s=%s \n", procfs_parameter, procfs_value);


    // check if given parameter is valid - if so convert it to it's value

    if(!strncmp(procfs_parameter, "timer.sec", PROCFS_MAX_SIZE)) {
    // is it timer.sec, convert it to int, assign it to timer_sec variable and restart timer 

	PROC_TO_INT(integer_data > 0 || timer_nsec >= 1000 , 
		    timer_sec, 
		    "timer.sec", 
		    printk(KERN_WARNING "timer.sec can't be 0 and timer.nsec < 1000 at the same time\n"));
	stop_timer();
	start_timer();
		    	

    } else if (!strncmp(procfs_parameter, "timer.nsec", PROCFS_MAX_SIZE) ) {
    // is it timer.nsec, convert it to int, assign it to timer_nsec variable and restart timer 

	PROC_TO_INT(timer_sec > 0 || integer_data >= 1000, 
		    timer_nsec, 
		    "timer.nsec", 
		    printk(KERN_WARNING "timer.sec can't be 0 and timer.nsec < 1000 at the same time\n"));
	stop_timer();
	start_timer();

    } else if (!strncmp(procfs_parameter, "process.pid", PROCFS_MAX_SIZE) ) {
    // is it process.pid, convert it to int, assign it to pid variable

	PROC_TO_INT(integer_data >= 0, 
		    pid, 
		    "process.pid", 
		    printk(KERN_WARNING "PID should be positive\n"));
	init_signal();
    
    } else {
    // in case a unknown parameter is given drop a message to kernel log

	printk(KERN_WARNING "Unknown parameter %s=%s\n", procfs_parameter, procfs_value);
    }

    
    return procfs_buffer_size;

error_write_proc:
    printk(KERN_WARNING "ProcFS paremter was writen in invalid format. Should be Parameter=value \n");
error_write_proc2:
    return -EFAULT;    // in case of any fail we return it
}

/* ProcFS handler structhre */
static const struct file_operations st_fops = {
    .owner      = THIS_MODULE,
    .open       = st_open,
    .read       = seq_read,
    .write       = st_write, 
    .llseek     = seq_lseek,
    .release    = single_release,
};





static int __init signal_test_init(void) {

    printk(KERN_INFO"Starting signal test module\n");

    timer_sec = 1;
    timer_nsec = 0;

    proc_create(PROC_ENTRY_FILENAME, 0, NULL, &st_fops);

    start_timer();

    return 0;
}
/* send_sig_info(SIGIO, &sinfo, task);
return 0;
} */

static void __exit signal_test_exit(void) {
    printk(KERN_INFO"Stopping signal test module\n");
    stop_timer();
    remove_proc_entry(PROC_ENTRY_FILENAME, NULL);
}

module_init(signal_test_init);
module_exit(signal_test_exit);


MODULE_AUTHOR ("Thomas Schmidt <t.schmidt(at)md-network.de>");
MODULE_DESCRIPTION ("HighR Timer based signals from kernel to user space");
MODULE_LICENSE("GPL");
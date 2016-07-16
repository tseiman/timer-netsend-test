/**
 *	[[TBD - rights header]] (c) Thomas Schmidt, 2016
 *	
 *	This kernel module demonstrates kernel high resolution timer
 *	and sends every timer event a UDP packet to network
 *	Timer and network settings can be configured over procfs
 *
 *	Tested Linux kernel: 4.4.1
 **/


/** 
 * 	Module's ProcFS configuration:
 * 
 *   	Configuration can be found in /proc/PROC_ENTRY_FILENAME (see define below)
 *   	The file contains following options:
 *		packet.size 		-  UDP packet size, maximal 1420, default MAX_MESSAGE_SIZE, e.g. "1420"
 *		timer.msec		-  timer milli seconds
 *		addr.remote.ip		-  remote IP address in dotted format, default "1.1.1.2" 
 *		addr.remote.port	-  remote UDP port, default "1234"
 *
 *   	Example to set configuration:  ~> echo "ethernet.dev=eth2" >/proc/udp_ktest
 *   	Example to read configuration: ~> cat /proc/udp_ktest
 *
 **/

/* name of the proc file entry */
#define PROC_ENTRY_FILENAME	"udp_ktest"

/* maximal size of read data */
#define PROCFS_MAX_SIZE 	512

/* maximal size of UDP message */
#define MAX_MESSAGE_SIZE 	1420


#define TRUE			1
#define FALSE			0


#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/types.h>
#include <linux/hrtimer.h>
#include <linux/string.h>
#include <linux/inet.h>
#include <linux/in.h>
#include <linux/netdevice.h>
#include <net/sock.h>
#include <linux/kthread.h> 

static unsigned int timer_msec; 					/* milli seconds of inter packet delay timer */
static unsigned int packet_size = 512;					/* UDP packet size, default 512 bytes */
static unsigned int remote_port = 1234;					/* remote port for UDP packet, default 1234 */
static unsigned long int remote_addr =  0x02010101;  			/* remote IP address in int32 format network byte order */
static char message[MAX_MESSAGE_SIZE];					/* buffer to store UDP message */
static int net_setup_ok = FALSE;					/* flag get TRUE in case the netpoll setup was ok */

static struct socket *clientsocket=NULL;

struct task_struct *task;

static char procfs_buffer[PROCFS_MAX_SIZE];				/* buffer to handle input data on write access (copied from user space) */
  
static unsigned long procfs_buffer_size = 0;				/* stores size of data written to proc and copied from user space */







/*
 * sets up network parameters and 
 * sends a packet to the network
 */

static void net_send(void) {
    int len;
    mm_segment_t oldfs;
    struct sockaddr_in destination;
    struct iov_iter iov_iter;
    struct msghdr msg;
    struct iovec iov;  
     
    if(!net_setup_ok) return;

    memset(&msg, 0, sizeof(msg));


    destination.sin_family = AF_INET;
    destination.sin_addr.s_addr = remote_addr; 
    destination.sin_port = htons(remote_port);

    msg.msg_name = &destination;
    msg.msg_namelen = sizeof(destination);
    msg.msg_flags = MSG_DONTWAIT | MSG_NOSIGNAL;

    iov.iov_base = message;
    iov.iov_len  = packet_size;

    iov_iter_init(&iov_iter, READ, &iov, 1, iov.iov_len);
    msg.msg_iter = iov_iter;

    oldfs = get_fs();
    set_fs( KERNEL_DS );
    len = sock_sendmsg( clientsocket, &msg );
    set_fs( oldfs );
    if( len < 0 ) printk( KERN_ERR "sock_sendmsg returned: %dn", len);

}




/*
 * configures netpoll API
 * in case this was successful the netpoll_setup_ok is set to TRUE
 * netpoll will dump some configuration information to kernel log
 */
static void setup_net(void) {

    if( clientsocket ) sock_release( clientsocket );

    if( sock_create( PF_INET,SOCK_DGRAM, IPPROTO_UDP,&clientsocket)<0 ) {
	printk( KERN_ERR "server: Error creating clientsocket.\n" );
	net_setup_ok = FALSE;
    }

    net_setup_ok = TRUE;

    
}


/* 
 * ProcFS IO
 * shows configuration on procfile read 
 */
static int st_show(struct seq_file *m, void *v) {
    seq_printf(m, "packet.size: %u\n", packet_size);
    seq_printf(m, "timer.msec: %u\n", timer_msec);
    seq_printf(m, "addr.remote.ip: %lu.%lu.%lu.%lu\n", (remote_addr & 0x000000ff), ((remote_addr & 0x0000ff00) >>8), ((remote_addr & 0x00ff0000) >>16), (remote_addr >>24));
    seq_printf(m, "addr.remote.port: %u\n", remote_port);
    
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
 * Macro only for st_write() function below,
 * which will convert data which is written to ProcFS
 * to an IP address converted IP address will be stored on success in given variable
 * on fail it jumps to error condition. It will log activities to kernel log.
 * Paremters:
 *	VARIABLE_NAME		- the variable where the data should be stored in
 *	PARAMTER_NAME		- the variable name as string for error or success message
 */
#define PROC_TO_IP( VARIABLE_NAME, PARAMETER_NAME) 						\
	integer_data = in_aton(procfs_value);							\
	snprintf(compare_back_buffer,16,"%d.%d.%d.%d",(integer_data & 0x000000ff), 		\
		    ((integer_data & 0x0000ff00) >>8), 						\
			((integer_data & 0x00ff0000) >>16), (integer_data >>24));		\
	printk(KERN_INFO "set %s to %s\n",PARAMETER_NAME, compare_back_buffer);			\
	if(strncmp(procfs_value,compare_back_buffer,16)) {					\
	    printk(KERN_WARNING "%s couldn't be parsed, incorrect IPv4 format: %s \n", 		\
		    PARAMETER_NAME, compare_back_buffer); 					\
	    goto error_write_proc2;								\
	}											\
	VARIABLE_NAME = integer_data;


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

    if(!strncmp(procfs_parameter, "timer.msec", PROCFS_MAX_SIZE)) {

	PROC_TO_INT(integer_data > 0 , 
		    timer_msec, 
		    "timer.msec", 
		    printk(KERN_WARNING "timer.msec can't be 0\n"));
		    	
    } else if (!strncmp(procfs_parameter, "packet.size", PROCFS_MAX_SIZE) ) {
    // is it packet.size, convert it to int, assign it to packet_size variable, this is automatically taken by netpoll 

	PROC_TO_INT(integer_data <= MAX_MESSAGE_SIZE, 
		    packet_size, 
		    "packet.size", 
		    printk(KERN_WARNING "packet.size can't be >%d but was %u \n", MAX_MESSAGE_SIZE, (unsigned int) integer_data));
		    
    } else if (!strncmp(procfs_parameter, "addr.remote.port", PROCFS_MAX_SIZE) ) {
    // is it addr.remote.port, convert it to int, assign it to remote_port variable and re-initialize netpoll

	PROC_TO_INT(integer_data > 1 && integer_data <  64535, 
		    remote_port, 
		    "addr.remote.port", 
		    printk(KERN_WARNING "addr.remote.port should be <64535 and >0 but was %u \n", (unsigned int) integer_data));
	setup_net();

    } else if (!strncmp(procfs_parameter, "addr.remote.ip", PROCFS_MAX_SIZE) ) {
    // is it addr.remote.ip, convert it to int (network byte order), assign it to remote_addr variable and re-initialize netpoll

	PROC_TO_IP( remote_addr, "addr.remote.ip");
	setup_net();

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



/*
 * function runs in a seperate thread,
 * handling high precision scheduling and trigger periodically
 * network sending function
 */
int net_thread(void *data) {
    ktime_t timeout = ktime_get();

    setup_net();

    memset(message, (int) 'x', MAX_MESSAGE_SIZE);
    timer_msec = 1000;

    
    while(!kthread_should_stop()) {
	net_send();	
	
	timeout = ktime_add_us(timeout, timer_msec);
	__set_current_state(TASK_UNINTERRUPTIBLE);
	schedule_hrtimeout_range(&timeout, 100, HRTIMER_MODE_ABS);
    }

    return 0;
}

/* 
 * initialisation of the module
 * initializes the UDP message buffer, 
 * sets up the timer and network functions and registers proc entry
 */ 
static int __init signal_test_init(void) {
    struct sched_param param = { .sched_priority = MAX_RT_PRIO - 1 };
    
    printk(KERN_INFO"Starting signal test module\n");


    proc_create(PROC_ENTRY_FILENAME, 0, NULL, &st_fops);

    task = kthread_create(&net_thread, NULL,"timer-netsend-test-udp");
    if (IS_ERR(task)) {
	printk(KERN_ERR "Failed to create timer-netsend-test-udp thread\n");
	return -ESRCH;
    }
    
    sched_setscheduler(task, SCHED_FIFO, &param);
    wake_up_process(task);
    
    return 0;
}

/* 
 * exit the module
 * stops timer and proc
 */ 

static void __exit signal_test_exit(void) {
     kthread_stop(task);  


    
    if( clientsocket ) sock_release( clientsocket );


    remove_proc_entry(PROC_ENTRY_FILENAME, NULL);
    printk(KERN_INFO"Signal test module stopped\n");

}

module_init(signal_test_init);
module_exit(signal_test_exit);


MODULE_AUTHOR ("Thomas Schmidt <thomas.schmidt@exfo.com>");
MODULE_DESCRIPTION ("HighR Timer based UDP sender");
MODULE_LICENSE("GPL");
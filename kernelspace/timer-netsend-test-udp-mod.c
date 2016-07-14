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
 *		timer.sec		-  timer seconds - can't be 0 if nano seconds less than 1000, e.g. "1"
 *		timer.nsec		-  timer nano seconds - can't be less than 1000 if seconds are 0, e.g. "1000"
 *		ethernet.dev		-  ethernet device packets should be send on, default DEFAULT_ETH_DEV, e.g. "eth0"
 *		addr.local.ip		-  local IP address in dotted format, default "1.1.1.9" 
 *		addr.local.port		-  local UDP port, default "1234"
 *		addr.remote.ip		-  remote IP address in dotted format, default "1.1.1.2" 
 *		addr.remote.port	-  remote UDP port, default "1234"
 *		addr.remote.mac		-  remote MAC address of receiving ethernet interface, default "01:02:03:04:05:06"
 *
 *   	Example to set configuration:  ~> echo "ethernet.dev=eth2" >/proc/udp_ktest
 *   	Example to read configuration: ~> cat /proc/udp_ktest
 *
 **/

/* name of the proc file entry */
#define PROC_ENTRY_FILENAME	"udp_ktest"

/* name of the default ethernet device */
#define DEFAULT_ETH_DEV		"eth0"

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
#include <linux/netdevice.h>
#include <linux/netpoll.h>

static unsigned int timer_sec; 						/* seconds of inter packet delay timer */
static unsigned int timer_nsec;						/* nano seconds of inter packet delay timer */
static unsigned int packet_size = 512;					/* UDP packet size, default 512 bytes */
static unsigned int remote_port = 1234;					/* remote port for UDP packet, default 1234 */
static unsigned int local_port = 1234;					/* local port for UDP packet, default 1234 */
static unsigned long int remote_addr =  0x02010101;  			/* remote IP address in int32 format network byte order */
static unsigned long int local_addr = 0x09010101;			/* local IP address in int32 format network byte order */
static u8 remote_mac[ETH_ALEN] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06};	/* remote MAC address default 01:02:03:04:05:06 */
static char ethernet_device[IFNAMSIZ];					/* buffer for ethernet device */
static char message[MAX_MESSAGE_SIZE];					/* buffer to store UDP message */
static int netpol_setup_ok = FALSE;					/* flag get TRUE in case the netpoll setup was ok */

// ?need? struct task_struct *task; 
static struct hrtimer htimer;						/* Structures to maintain high resolution timer information */
static ktime_t kt_period;
static struct netpoll* np = NULL;					/* structures to maintain netpoll information */
static struct netpoll np_t;

static char procfs_buffer[PROCFS_MAX_SIZE];				/* buffer to handle input data on write access (copied from user space) */
  
static unsigned long procfs_buffer_size = 0;				/* stores size of data written to proc and copied from user space */



/* 
 * callback for the high resolution timer 
 * in case the netpoll setup was ok, UDP packet is send
 * and timer is re-armed
 */
static enum hrtimer_restart timer_callback(struct hrtimer * timer) {	
    if(netpol_setup_ok) netpoll_send_udp(np,message,packet_size);    
    
    hrtimer_forward_now(timer, kt_period);
    return HRTIMER_RESTART;
}


/* 
 * initilizes the high resolution timer with data from configuration (e.g. procfs)
 * this is called as well when new configuration is writen 
 */
static void start_timer(void) {
    kt_period = ktime_set(timer_sec, timer_nsec); //seconds,nanoseconds
    hrtimer_init (& htimer, CLOCK_REALTIME, HRTIMER_MODE_REL);
    htimer.function = &timer_callback;
    hrtimer_start(& htimer, kt_period, HRTIMER_MODE_REL);
}

/*
 * cancels any timer activity
 * caled as well before start_timer() in case of reconfiguration
 */
static void stop_timer(void) {
    hrtimer_cancel( &htimer );    
}


/*
 * configures netpoll API
 * in case this was successful the netpoll_setup_ok is set to TRUE
 * netpoll will dump some configuration information to kernel log
 */
static void setup_net(void) {
    np_t.name = "LRNG";
    strlcpy(np_t.dev_name, ethernet_device, IFNAMSIZ);
    np_t.local_ip.ip =  local_addr;
    np_t.remote_ip.ip =  remote_addr;
    np_t.local_port = local_port;
    np_t.remote_port = remote_port;
    memcpy(np_t.remote_mac, remote_mac,6);
    netpoll_print_options(&np_t);
    if(netpoll_setup(&np_t)) {
	printk(KERN_WARNING "can't setup netpoll, invalid parameters\n");
    } else {
	np = &np_t;
	netpol_setup_ok = TRUE;
	printk(KERN_INFO "netpoll initialized\n");
    }
}


/* 
 * ProcFS IO
 * shows configuration on procfile read 
 */
static int st_show(struct seq_file *m, void *v) {
    seq_printf(m, "packet.size: %u\n", packet_size);
    seq_printf(m, "timer.sec: %u\n", timer_sec);
    seq_printf(m, "timer.nsec: %u\n", timer_nsec);
    seq_printf(m, "ethernet.dev: %s\n",ethernet_device);
    seq_printf(m, "addr.local.ip: %lu.%lu.%lu.%lu\n", (local_addr & 0x000000ff), ((local_addr & 0x0000ff00) >>8), ((local_addr & 0x00ff0000) >>16), (local_addr >>24));
    seq_printf(m, "addr.local.port: %u\n", local_port);
    seq_printf(m, "addr.remote.ip: %lu.%lu.%lu.%lu\n", (remote_addr & 0x000000ff), ((remote_addr & 0x0000ff00) >>8), ((remote_addr & 0x00ff0000) >>16), (remote_addr >>24));
    seq_printf(m, "addr.remote.port: %u\n", remote_port);
    seq_printf(m, "addr.remote.mac: %02x:%02x:%02x:%02x:%02x:%02x\n",remote_mac[0],remote_mac[1],remote_mac[2],remote_mac[3],remote_mac[4],remote_mac[5]);
    
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

    } else if (!strncmp(procfs_parameter, "addr.local.port", PROCFS_MAX_SIZE) ) {
    // is it addr.local.port, convert it to int, assign it to local_port variable and re-initialize netpoll

	PROC_TO_INT(integer_data > 1 && integer_data <  64535, 
		    local_port, 
		    "addr.local.port", 
		    printk(KERN_WARNING "addr.local.port should be <64535 and >0 but was %u \n", (unsigned int) integer_data));
	setup_net();

    } else if (!strncmp(procfs_parameter, "addr.local.ip", PROCFS_MAX_SIZE) ) {
    // is it addr.local.ip, convert it to int (network byte order), assign it to local_addr variable and re-initialize netpoll

	PROC_TO_IP( local_addr, "addr.local.ip");
	setup_net();

    } else if (!strncmp(procfs_parameter, "addr.remote.ip", PROCFS_MAX_SIZE) ) {
    // is it addr.remote.ip, convert it to int (network byte order), assign it to remote_addr variable and re-initialize netpoll

	PROC_TO_IP( remote_addr, "addr.remote.ip");
	setup_net();

    } else if (!strncmp(procfs_parameter, "addr.remote.mac", PROCFS_MAX_SIZE) ) {
    // is it addr.remote.mac, convert it to byte array, assign it to remote_mac variable and re-initialize netpoll

	if (!mac_pton(procfs_value, remote_mac)) {
	    printk(KERN_WARNING "addr.remote.mac couldn't be parsed incorrect MAC address format: %s \n", procfs_value); 
	    goto error_write_proc2;		
	}
	setup_net();

    } else if (!strncmp(procfs_parameter, "ethernet.dev", PROCFS_MAX_SIZE) ) {
    // is it ethernet.de, copy it to ethernet_device variable and re-initialize netpoll

	strncpy(ethernet_device,procfs_value,IFNAMSIZ);
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
 * initialisation of the module
 * initializes the UDP message buffer, 
 * sets up the timer and network functions and registers proc entry
 */ 
static int __init signal_test_init(void) {

    printk(KERN_INFO"Starting signal test module\n");
    memset(message, (int) 'x', MAX_MESSAGE_SIZE);

    timer_sec = 1;
    timer_nsec = 0;
    strcpy(ethernet_device, DEFAULT_ETH_DEV);    
    proc_create(PROC_ENTRY_FILENAME, 0, NULL, &st_fops);
    
    setup_net();

    start_timer();

    return 0;
}

/* 
 * exit the module
 * stops timer and proc
 */ 

static void __exit signal_test_exit(void) {
    printk(KERN_INFO"Stopping signal test module\n");
    stop_timer();
    remove_proc_entry(PROC_ENTRY_FILENAME, NULL);
}

module_init(signal_test_init);
module_exit(signal_test_exit);


MODULE_AUTHOR ("Thomas Schmidt <t.schmidt(at)md-network.de>");
MODULE_DESCRIPTION ("HighR Timer based UDP sender");
MODULE_LICENSE("GPL");
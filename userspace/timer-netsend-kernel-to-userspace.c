#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <ctype.h>

#define PROC_FILE_SIGNALTEST_PID "/proc/signal_ktest"
#define true 1
#define SERVER "1.1.1.2"
#define BUFLEN 512  //Max length of buffer
#define PORT 1234   //The port on which to send data

#define TEST_MALLOC_SIZE 250000000 // 250 Mbyte for test malloc

struct sockaddr_in si_other;
int  s, i, slen=sizeof(si_other);
char *message;
int message_len = BUFLEN;
unsigned long msg_sent_count;

void signal_handler_module (int signum){
    if (signum == SIGIO) {
	++msg_sent_count;
	printf ("\033[u%lu",msg_sent_count);
	fflush( stdout );    

	if (sendto(s, message, message_len , 0 , (struct sockaddr *) &si_other, slen)==-1) {
    	    fprintf(stderr,"sendto() failed\n");
        }
    
	return;
    }
}

void signal_handler_exit (int signum){
	FILE *fp;
	
	printf("\nde-registering PID from kernel module, exiting\n");
	
	if( access(PROC_FILE_SIGNALTEST_PID , F_OK ) != -1 ) {
	    fp=fopen(PROC_FILE_SIGNALTEST_PID, "w");
	    fprintf(fp, "process.pid=0\n");
	    fclose(fp);
	}
     
	free(message);
	exit(0);
}


int main (int argc, char **argv) { 
    FILE *fp;
    pid_t pid = getpid();
    int c,i;
    msg_sent_count = 0;
    opterr = 0;

    while ((c = getopt (argc, argv, "b:h")) != -1) {
    switch (c) {
	    case 'b':
    		message_len = atoi(optarg);
    		if(message_len == 0 || message_len >1420) {
    		    fprintf(stderr, "Please give numeric value >0 and <1420 for message length. Instead it was %s\n", optarg);
    		    exit(2);
    		}
    		
    		break;
	    case 'h':
		printf("\n	Packet sender which get timer signal from kernel module\n\n");
		printf("	-b N	size of payload in ethernet packet >0 and <= 1420, default is 512\n");
		exit(0);

    	    case '?':
    		if (optopt == 'b') 	fprintf (stderr, "Option -%c requires an argument.\n", optopt);
    		else if (isprint (optopt)) fprintf (stderr, "Unknown option `-%c'.\n", optopt);
    		else fprintf (stderr, "Unknown option character `\\x%x'.\n",optopt);
    		exit(1);
    	    default: abort ();
        }
     }

    printf("Message length is %d\n", message_len);
    message = malloc(message_len);
     if (message == 0) {
        fprintf(stderr, "malloc() failed\n");
	exit(3);
    }
    
    if( access(PROC_FILE_SIGNALTEST_PID , F_OK ) == -1 ) {
	fprintf(stderr,"\nThe proc file \"%s\" doesnt exist is the module signal_test_mod loaded ?\n\n", PROC_FILE_SIGNALTEST_PID);
	exit(-1);
    } 

    fp=fopen(PROC_FILE_SIGNALTEST_PID, "w");
    fprintf(fp, "process.pid=%d\n",pid);
    fclose(fp);
     



    signal(SIGIO, signal_handler_module);
    signal(SIGINT, signal_handler_exit);
    printf("My PID is %d - registering it to kernel module\n",pid);
    printf(" Hit CTRL-C to stop\n");

    printf ("Sending packet No: \033[s-");
    fflush( stdout );    
    
    if ( (s=socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) == -1) {
        perror("socket() failed");
	exit(-1);
    }
    memset((char *) &si_other, 0, sizeof(si_other));
    si_other.sin_family = AF_INET;
    si_other.sin_port = htons(PORT);
    
    if (inet_aton(SERVER , &si_other.sin_addr) == 0) {
        fprintf(stderr, "inet_aton() failed\n");
        exit(-2);
    }
 
    memset(message, (int) 'x', message_len);
    
    while (true) {
	pause();
    }
    return 0;
}
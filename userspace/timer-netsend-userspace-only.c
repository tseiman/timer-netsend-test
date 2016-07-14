#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <ctype.h>
#include <time.h>


#define PROC_FILE_SIGNALTEST_PID "/proc/signal_test_mod_pid"
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
unsigned second = 1;
unsigned nsecond = 0;
timer_t gTimerid;


void signal_handler_timer (int signum){
    if (signum == SIGALRM) {
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
    struct itimerspec timerconf;

	
    printf("\nFetched CTRL-C, exiting.\n");

    timerconf.it_value.tv_sec = 0;
    timerconf.it_value.tv_nsec = 0;
    timerconf.it_interval.tv_sec = 0;
    timerconf.it_interval.tv_nsec = 0;

    timer_settime (gTimerid, 0, &timerconf, NULL);
    free(message);
    fflush( stdout );    

    exit(0);
}


int main (int argc, char **argv) { 
    FILE *fp;
    pid_t pid = getpid();
    int c,i;
    msg_sent_count = 0 ;
    opterr = 0;
    struct itimerspec timerconf;

    while ((c = getopt (argc, argv, "b:s:n:h")) != -1) {
    switch (c) {
	    case 'b':
    		message_len = atoi(optarg);
    		if(message_len == 0 || message_len >1420) {
    		    fprintf(stderr, "Please give numeric value >0 and <1420 for message length. Instead it was %s\n", optarg);
    		    exit(2);
    		}
    		
    		break;
	    case 's':
    		second = atoi(optarg);
    		break;
	    case 'n':
    		nsecond = atoi(optarg);
    		break;
	    case 'h':
		printf("\n	User space only packet sender, packet size and inter frame gap time can be defined with timer\n\n");
		printf("	-b N	size of payload in ethernet packet >0 and <= 1420, default is 512\n");
		printf("	-s N	timer in seconds -s and -n can never be both 0 at same time, default is 1\n");
		printf("	-n N	timer in nano seconds cannot be <1000 in case -s = 0, default is 0\n\n");
		exit(0);
    	    case '?':
    		if (optopt == 'b') 	fprintf (stderr, "Option -%c requires an argument.\n", optopt);
    		else if (isprint (optopt)) fprintf (stderr, "Unknown option `-%c'.\n", optopt);
    		else fprintf (stderr, "Unknown option character `\\x%x'.\n",optopt);
    		exit(1);
    	    default: abort ();
        }
     }
    if(second == 0 && nsecond < 1000) {
	fprintf(stderr, "Second = 0 and nsecond  < 1000 , not a good idea, Abort\n");
	exit(2);
    }
    printf("Message length is %d\n", message_len);
    printf("Timer is  %useconds and %unseconds \n",second,  nsecond);
    message = malloc(message_len);
     if (message == 0) {
        fprintf(stderr, "malloc() failed\n");
	exit(3);
    }



    signal(SIGALRM, signal_handler_timer);

    signal(SIGINT, signal_handler_exit);


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


    timerconf.it_value.tv_sec = second;
    timerconf.it_value.tv_nsec = nsecond;
    timerconf.it_interval.tv_sec = second;
    timerconf.it_interval.tv_nsec = nsecond;

    timer_create (CLOCK_REALTIME, NULL, &gTimerid);
    timer_settime (gTimerid, 0, &timerconf, NULL);


    while (true) {
	pause();
    }
    return 0;
}

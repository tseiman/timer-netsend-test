
obj-m += timer-netsend-test-signal-mod.o timer-netsend-test-udp-sock-thread-mod.o
#udp-test-mod.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:	
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean



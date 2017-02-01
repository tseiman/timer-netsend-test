

CC=gcc
CFLAGS=-I.
DEPS =
BIN = timer-netsend-kernel-to-userspace timer-netsend-userspace-only 



all:	$(BIN)

.PHONY: clean

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

timer-netsend-kernel-to-userspace: timer-netsend-kernel-to-userspace.o
	$(CC) -o $@ $^ $(CFLAGS) 


timer-netsend-userspace-only.o: timer-netsend-userspace-only.c
	$(CC) -c -o $@ $< $(CFLAGS) -lrt -lpthread $(LDFLAGS)

timer-netsend-userspace-only: timer-netsend-userspace-only.o
	$(CC) -o $@ $^ $(CFLAGS) -lrt -lpthread $(LDFLAGS)


clean:
	rm -f $(BIN) *.o




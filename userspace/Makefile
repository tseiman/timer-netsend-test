

CC=gcc
CFLAGS=-I.
DEPS =
BIN = timer-netsend-kernel-to-userspace timer-netsend-userspace-only 



all:	$(BIN)

.PHONY: clean

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

timer-netsend-kernel-to-userspace: timer-netsend-kernel-to-userspace.o
	gcc -o $@ $^ $(CFLAGS)

timer-netsend-userspace-only: timer-netsend-userspace-only.o
	gcc -o $@ $^ $(CFLAGS) -lrt


clean:
	rm -f $(BIN) *.o




#!/bin/bash

FILE=/proc/udp_ktest

CONFIGURE[1]="addr.remote.mac=00:0a:cd:27:76:23"
CONFIGURE[2]="addr.local.ip=192.168.2.147"
CONFIGURE[3]="addr.remote.ip=192.168.2.101"
CONFIGURE[4]="packet.size=10"
CONFIGURE[5]="timer.nsec=10000"
CONFIGURE[6]="timer.sec=0"
CONFIGURE[7]="ethernet.dev=ens33"



if [ ! -e $FILE ]; then
    echo "  $FILE does not exist - is timer-netsend-test-udp-mod loaded ?"
    exit -1;
fi

echo "  Configure timer-netsend-test-udp-mod:"

for CFG_ENTRY in "${CONFIGURE[@]}"
do
    echo "     Setting $CFG_ENTRY"
    echo "$CFG_ENTRY" >$FILE
done

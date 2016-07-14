#!/bin/bash


RUNTIME=20

NUM_CPUS=`cat /proc/cpuinfo | grep  '^processor[[:space:]]*:[[:space:]]*[0-9]\+$' | wc -l`


trap "killall stress-ng 2>&1>/dev/null; rm -f /tmp/cpu_stress_control; exit" SIGHUP SIGINT SIGTERM

pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd`
popd > /dev/null


for I in $(seq 0 10 100); do
    echo "limiting to $I% CPU "
    echo $I >/tmp/cpu_stress_control
    ${SCRIPTPATH}/../tools/stress-ng/stress-ng --cpu 2   -l $I -t $RUNTIME    
done

rm -f /tmp/cpu_stress_control
killall stress-ng 2>&1>/dev/null

# Timer Netsend
A test suite to demonstrate time accuracy of timer based network activity
<hr />

This document is not complete yet. some passages are marked with "TBC"="To be Completed"

## Content:
- [Note] (#note)
- [Overview] (#overview)
- [Requires] (#requires)
- [Assumptions] (#assumptions)
- [The setup in a nutshell] (#the-setup-in-a-nutshell)
- [Overview of scripts and binaries] (#overview-of-scripts-and-binaries)
  + [Folder "scripts"] (#folder-scripts)
    - [ecp3-ethtest-statreader.pl] (#ecp3-ethtest-statreaderpl)
    - [setup_udp-test-mod.sh] (#setup_udp-test-modsh)
    - [simple_packet_test.pl] (#simple_packet_testpl) 
    - [poll_cpustatus.pl] (#poll_cpustatuspl)
    - [cpu_stress_control.sh] (#cpu_stress_controlsh)
    - [csv2html.pl] (#csv2htmlpl)
  + [Folder "userspace"] (#folder-userspace)
    - [timer-userspace-only] (#timer-userspace-only)
    - [timer-kernel-to-userspace] (#timer-kernel-to-userspace)
  + [Folder "kernelspace"] (#folder-kernelspace)
    - [timer-netsend-test-signal-mod] (#timer-netsend-test-signal-mod)
    - [timer-netsend-test-udp-sock-thread-mod] (#timer-netsend-test-udp-sock-thread-mod)
  + [Folder "tools"] (#folder-tools)
    - [stress-ng] (#stress-ng)
- [Setting up ETH Interface] (#setting-up-eth-interface)
- [Test description] (#test-description)
    + [Userspace process only test] (#userspace-process-only-test)
    + [Userspace sender process triggered by kernel] (#userspace-sender-process-triggered-by-kernel)
    + [Kernel module realtime scheduling and packet sending] (#kernel-module-realtime-scheduling-and-packet-sending)
    + [CPU sets with userspace process] (#cpu-sets-with-userspace-process)
- [Setting up test processes on the tested plattform] (#setting-up-test-processes-on-the-tested-plattform)
- [Setting up load for tested plattform] (#setting-up-load-for-tested-plattform)
- [FPGA board meassurment description] (#fpga-board-meassurment-description)
- [FPGA board configuration] (#fpga-board-configuration)
- [Links] (#links)

============================================================

## Note
This is experimetnal software to test the behavior of linux in load conditions. It is not meant in any way as productional software or as 
example of good linux (linux) programming. 

**>>>> Any damage caused by this software or softweare derived from it, is in the responsibility of the user ! <<<<**


## Overview
Timer-Test suite contains a couple of scripts and programs to generate UDP packets on a System Under Test (SUT) computer 
and to meassure the Network udp send() stability in dependency of the SUT system load. The Network performance is meassured with
a dedicated FPGA setup.
    
The Suite consist of following parts:
- script to obtain meassurment of CPU utilisation on the SUT
- script to obtain meassurment of the FPGA
- script & binary to generate CPU load
- alternatively different approaches to generate network UDP traffic either purly in user space,  mixed user space and kernel space and pure kernel space, supposed to run on SUT.
- scripts to generate graphs from the meassurements.

## Requires
- gcc >4.0
- Linux Kernel headers
- Linux Kernel >2.6
- Perl >= 5.2
- linux stress-ng tool (already included here in tools) http://smackerelofopinion.blogspot.de/2014/06/stress-ng-updated-system-stress-test.html 

## Assumptions
- FPGA Lattice ECP3 Versa development board and System Under Test host are directly connected via ethernet cable
- FPGA Board has MAC 01:02:03.04:05:06 and doesn't support IP layer or ARP
- to sattisfy system under test host the network interface for the FPGA board assuned to have IP 1.1.1.2/24 The system under test hosts network interface itself assumed to have 1.1.1.9/24
- ARP entry needs to be set manualy


## The setup in a nutshell

    +------------------------+                        +--------------------+           +---------------------+
    |   System Under Test    |                        | Lattice Versa ECP3 |           |      Monitoring     |
    |         Host           |                        |  Evaluation Board  |           |       Computer      |
    | ====================== |                        |        FPGA        |           |                     |
    |                        |                        |  meassuring delay  |           | Runs:               |
    | Runs:                  |                        | between incomming  |           |  - script to poll   |
    |  - traffic generator   |                        |      packets       |           |    FPGA meassurment |
    |    sending UDP packets |                        |                    |           |                     |
    |  - CPU stresser        |                        |              RS232 +--->--->---+ FTDI, USB UART      |
    |  - CPU monitor script  |                        |         38400, 8N2 |           |                     |
    |                        |     1GBit direct       |                    |           |                     |
    |          eth interface +---->---->---->---->----+ FPGA PHY           |           |                     |
    |             1.1.1.9/24 |     Ethernet Cable     | 01:02:03:04:05:06  |           |                     |
    +------------------------+                        +--------------------+           +---------------------+
    
    

## Overview of scripts and binaries


### Folder "scripts":
        
#### ecp3-ethtest-statreader.pl

This script reads measurement data from Lattice ECP3 Versa development board via FTDI/RS232.

The FPGA on the ECP3 board needs to be configured to run the ethernet analysis configuration to meassure
Inter Packet delay (TBD- give the baby a good name). This means that the FPGA setup will count the time needed 
from one packet to the next - where all packets with the right destination ethernet MAC wil be acceptend and meassured.
The measurement will be reset on each RS232 "(G)et" read. The FPGA will also store and analize minimum and maximum
inter packet delay to give an idea about inter packet delay variance and the number of received packets which enables 
the ecp3-ethtest-statreader.pl script to calculate avarage inter packet delay.
The FPGA setup assumes that sender (SystemUnderTest) and reciever (FPGA meassurement board = Lattice ECP3 Versa Dev board) 
are directly linked via ethernet cable to avoid disturbance.
The counters (summary, min, max - inter packet delay) are not given directly in seconds (or nano seconds) it is given in 125MHz
clock ticks - and needs to be devided by 125000000 to get the time in seconds, which is done by the script.
Please check as well FPGA meassuement documentation for further information.
		
The ecp3-ethtest-statreader.pl script takes several command line parameters:

	    -h              - help message and exit
	    -v              - verbose loging to STDOUT, set as well when no CSV file given
	    -f <FILENAME>   - log to this file in CSV format, if not given -v is automatically enabled
	    -d <DEVICE>     - sets the tty serial device default is /dev/ttyUSB1
	    -i <SEC>        - poll interval in seconds, default is 1 second

The script will loop with a delay of <SEC> (default 1) between each new data poll, until CTRL-C (SIGINT) occours.
	
The script reads the data over RS232 by sending 'G' for (g)et data. The FPGA will send then the data structure
contains following fields: 
- total summary of inter packet delay of all received packets in number of 125MHz clock ticks since last (g)et, 5-bytes host byte order
- number of packets received since last (g)et, 3-bytes host byte order
- minimum inter packet delay occourd since last (g)et in number of 125MHz clock ticks, 4-bytes host byte order
- maximum inter packet delay occourd since last (g)et in number of 125MHz clock ticks, 4-bytes host byte order
- checksum - this is a 8 bit filed which is simply summed up from all 16 bytes transmitted from the other fields the checksum will overflow the final value after sum of 16 bytes is stored in the last byte, 1-byte

        +----------------+--------------+------------+------------+-----------+
        |   total time   | # of packets |    min     |    max     | checksum  |
    	+---- 5bytes ----+--- 3bytes ---+-- 4bytes --+-- 4bytes --+-- 1byte --+

In case the script detects a problem with the checksum, the script will request the data again by sending 'R' to (r)etransmit the last dataset.
This is repeated until data with a correct checksum is received.
The ecp3-ethtest-statreader.pl converts the values in readable format and displays those or writes those to a CSV file. 
It is supposed to run on the monitoring computer.


#### setup_udp-test-mod.sh
this script helps to configure the pure kernel space UDP sender, feel free to edit content. It is supposed to run on the SUT.
    
    
#### simple_packet_test.pl
this is a simple perl based UDP packet sender to test the FPGA setup. 
It assumes that the local sender's host IP is configured in a 1.1.1.x/24 network 
and that the receiver has IP 1.1.1.2 and MAC address 01:02:03:04:05:06 (=FPGA ECP Dev Board).
As the Development board does't support ARP - it will create an ARP entry in case it is not present.
The script takes as parameter 
    -p		packet size in bytes, e.g. 1420
    -d		inter packet delay in micro seconds, e.g. 1000000 (=1 sec)

Feels free to edit the script for Network settings etc.
    
    
#### poll_cpustatus.pl
this Perl script polls the CPU utilisation and writes it either to STDOUt or to a CSV file. The CSV file has the format
        Unix_Time,CPU_Usage,
	        
where Unix_Time is the time after 1st Jan 1970 in seconds and CPU usage the utilisation of the CPU (sys + user) over all 
installed CPUs in percent.

The script can get few parameters, mainly:    
	    
    -i <SEC>        - the poll interval in seconds, default is 1 second
    -f <FILENAME>   - the CSV file where the meassurements are written to in above documented format. 
                              If not given, CPU utilisation is written to STOUT.

poll_cpustatus.pl should run on the System Under Test (SUT)
                    

#### cpu_stress_control.sh
this script should run as well on the System Under Test (SUT) Computer and untilizes the CPUs to test the impact on the network performance
which is generated wit the network testing programs. This script needs to be edited and adapted to to needs of the SUT system.
This script makes use of the stress-ng tool which needs to be compiled before. The script expects the stress-ng binary in tools/stress-ng/ path.
	
	
#### csv2html.pl
creates dygraph HTML files from csv files and uses a special HTML file as template. 
It expect the first CSV column to be Unix Time in seconds after 1st Jan 1970. 
This scripts takes a number of command line arguments which are mandatory. E.g.:
    --template 	<templatefile.html> 	the special template file which is populated with the statistics data from CSV file.
					The script folder contains already a analysis.template.html file for this purpose.
						
    --outfile 	<outfile.html>		The HTML file generated from HTML template and CSV data.
    
    --inputfile <file.csv> 		The source statistics data in CSV format, expected to have first column to be Unix Time
					and then data. The last value needs to be terminate with ',\n'.
					
    --headline <headline>  		Headline of the Grpah.
    
    --ycaption <y caption> 		Y-Axis caption of the graph.
    
    --eventfile <eventfile>		This is the only optional parameter and gives possibility to load a second CSV file with the format
					    UnixTime,EventDescription,
					It will create anntotations in the graph highlighting special events (e.g. manually logged).

### Folder "userspace":
    
#### timer-userspace-only
this program generates UDP packets purely in userspace. It might be executed with elevated rights and priority. 
This program takes couple of command line parameters:
    -b N	the size of payload in UDP packet >0 and <= 1420 (because of MTU - IP+UDP Header), default is 512
    -s N	timer in seconds -s and -n can never be both 0 at same time means the total time must be always 
		larger than 1000 nano seconds.
    -n N	timer in nano seconds cannot be <1000 in case -s = 0, default is 0

All other timer test kernel modules and programs should be stopped or unloaded.


#### timer-kernel-to-userspace
this program demonstrate a split of functionality where the network part is implemnted in this executable in user space
and the the timer part in the kernel module "timer-netsend-test-signal-mod". The module  "timer-netsend-test-signal-mod" runs a 
kernel HRTimer and triggers on each timer event a system signal, sent to this "timer-kernel-to-userspace" process.
This program takes a command line parameters:
    -b N	the size of payload in UDP packet >0 and <= 1420 (because of MTU - IP+UDP Header), default is 512
	
Befor running this program the module "timer-netsend-test-signal-mod" must be load first, because this programm registeres itself
with the kernel module. Please read as well "timer-netsend-test-signal-mod" description.

    	
### Folder "kernelspace":
    
Modules might be loaded with "~> insmod <module name.ko>" unlaoded with "~> rmmod <module name>". 
The modules will (depending on kernel configuration) generating a "Tainted" stack trace in kernel log - which should be ok for the moment.
All modules are intend to run on the SUT system.
    
PLEASE NOTE: this are experimental modules and might crash the system

#### timer-netsend-test-signal-mod
this module runs a timer and on each timer event a SIGIO signal is sent to the process which might be registered.
This module is made to run with the user space program "timer-kernel-to-userspace". Please read this description as well above.
The module creates a proc entry "/proc/signal_ktest" which contains 3 parameters and which are used to configure the
module during runtime. This are:

    timer.sec		- the timer interval in seconds, default is 1, it is not allowed to have this value <1 in case timer.nsec is <1000
    timer.nsec		- the timer interval in nano seconds, default is 0, it is not allowed to have this value <1000 in case timer.sec is 0
    process.pid		- the PID of the process which should get the SIGIO signal
    
The configuration might be read by giving commadline command:
    ~> cat /proc/signal_ktest
	    
This configuration migth be updated by writing new value to the parameter e.g.:
    ~> echo "process.pid=1234" >/proc/signal_ktest

Please note the '=' between parameter and value.


#### timer-netsend-test-udp-sock-thread-mod

this module runs standalone in kernel space and implemnts the scheduling in a separated kernel thread and with high precision scheduling 
UDP send is implemetned with the kernel socket "API".

The module creates a proc entry "/proc/udp_ktest" which contains 4 parameters and which are used to configure the
module during runtime. To configure the module the parameters are:


    packet.size		- the UDP payload - has not to be 0 and not to be >1420 bytes (because of MTU - IP+UDP Header), default is 512
    timer.usec		- the timer interval in micro seconds, default is 1000000, it is not allowed to have this value <1
    addr.remote.ip	- gives the target IP, default is "1.1.1.2"
    addr.remote.port	- gives the remote receiver UDP port, default is "1234"

The configuration might be read by giving commadline command:
    ~> cat /proc/udp_ktest
	    
This configuration migth be updated by writing new value to the parameter e.g.:
    ~> echo "packet.size=1420" >/proc/udp_ktest

Please note the '=' between parameter and value.
When this module is loaded, no other timer-netsend-test module should be loaded - or not any other timer-netsend-test user space process should run.



### Folder "tools":
    
#### stress-ng
this tool is used to utilize the CPU of the System Under Test (SUT) to test it's beahvior. The script "cpu_stress_control.sh"
uses this tool. It is downloaded http://smackerelofopinion.blogspot.de/2014/06/stress-ng-updated-system-stress-test.html and copied here
to keep compatibility with the scripts.



## Setting up ETH Interface:

- assuming, even there is no IP and ARP stack implemented on measurement FPGA card the IP to be 1.1.1.2/24

- assuming meassurement Card has ETH MAC 01:02:03:04:05:06, and all ethernet packets are sent to this MAC will be counted & meassured

- well knowing that working as root user is a risk, all commands are given as root user

- in ./scripts folder is a script "setup-interface.sh" which does nessesary operations, however there is no security which checks that accedently a wrong ethernet interface is changed. Use it on your own risk.

- Set test computers ETH interface to IP e.g. 1.1.1.9 e.g. by giving command:
    ~> ifconfig eth0 1.1.1.9 netmask 255.255.255.0

- place ARP entry by giving
    ~> arp -s 1.1.1.2 01:02:03:04:05:06


## Test description
A number of scenarios can be performed with this testsuite to observe the behavior of a linux system when sending network packets in 
relation to the system CPU utilisation and disclose the impact of different implementations.
As an example the implementations can perform following tests:
- Maximum achivable packet rate in relation to CPU utilisation
- Impact of CPU Utilisation to the network sending performance

The next 3 sections describe the different implementations which have been prepared:
### Userspace process only test
For maximum performance test (= 512 byte packets per second maximum) the "userspace/timer-userspace-only" program can be started in an root context with the following command:
```bash
    ~/work/timer-netsend-test/userspace# ./timer-netsend-userspace-only -s 0 -n 1000
```
1000 Nano seconds are the minimum sleep time - otherwise the system might be overloaded.
The maximum achivable packet rate can be observed by using "ecp3-ethtest-statreader.pl", the CPU utilisation can be recorded by using "poll_cpustatus.pl".

For testing the dependency of CPU utilisation to packet send rate the script "scripts/cpu_stress_control.sh" is started without parameters in parallel to the 
"userspace/timer-userspace-only" program. The sleep time might be selected for one case that a very low packet rate is send (eg. 5pps) and for a second case the 
maximum packet rate is send. The minimum, average and maximum inter packet delay can be observed with the "ecp3-ethtest-statreader.pl" script. 
The effective CPU utilisation can be recorded by using "poll_cpustatus.pl".
The data from CPU utilisation observation and the minimum, average and maximum inter packet delay will show the relation of CPU utilisation and ability to schedule packets for sending.

### Userspace sender process triggered by kernel
For maximum performance test (= 512 byte packets per second maximum) the kernel module "timer-netsend-test-signal-mod" need to be loaded and the 
program "userspace/timer-kernel-to-userspace" has to be started. The kernel module need to be configured over the proc file system to run with 0 seconds and 1000 nano seconds sleep.
1000 Nano seconds are the minimum sleep time - otherwise the system might be overloaded.
The maximum achivable packet rate can be observed by using "ecp3-ethtest-statreader.pl", the CPU utilisation can be recorded by using "poll_cpustatus.pl".

For testing the dependency of CPU utilisation to packet send rate the script "scripts/cpu_stress_control.sh" is started without parameters in parallel to the 
kernel module "timer-netsend-test-signal-mod" and the "userspace/timer-kernel-to-userspace" program.
The sleep time might be selected for one case that a very low packet rate is send (eg. 5pps) and for a second case the 
maximum packet rate is send. The minimum, average and maximum inter packet delay can be observed with the "ecp3-ethtest-statreader.pl" script. 
The effective CPU utilisation can be recorded by using "poll_cpustatus.pl".
The data from CPU utilisation observation and the minimum, average and maximum inter packet delay will show the relation of CPU utilisation and ability to schedule packets for sending.


### Kernel module realtime scheduling and packet sending
For maximum performance test (= 512 byte packets per second maximum) the kernel module "timer-netsend-test-udp-sock-thread-mod" need to be loaded and
configured over the proc file system to run with 1 micro second sleep.
The maximum achivable packet rate can be observed by using "ecp3-ethtest-statreader.pl", the CPU utilisation can be recorded by using "poll_cpustatus.pl".

For testing the dependency of CPU utilisation to packet send rate the script "scripts/cpu_stress_control.sh" is started without parameters in parallel to the 
kernel module "timer-netsend-test-udp-sock-thread-mod".
The sleep time might be selected for one case that a very low packet rate is send (eg. 5pps) and for a second case the 
maximum packet rate is send. The minimum, average and maximum inter packet delay can be observed with the "ecp3-ethtest-statreader.pl" script. 
The effective CPU utilisation can be recorded by using "poll_cpustatus.pl".
The data from CPU utilisation observation and the minimum, average and maximum inter packet delay will show the relation of CPU utilisation and ability to schedule packets for sending.


### CPU sets with userspace process
For maximum performance test (= 512 byte packets per second maximum) the "userspace/timer-userspace-only" program can be started in an root context with the following command:
    ~/work/timer-netsend-test/userspace# ./timer-netsend-userspace-only -s 0 -n 1000
1000 Nano seconds are the minimum sleep time - otherwise the system might be overloaded.
The process PID need to be determined by using top command or similar. A cpu set need to be created by using command (one CPU will be reserved and no process will run on it):
```bash
    cset shield -c 1
```
The process of "timer-netsend-userspace-only" need to be transfered to this CPUSet by using command:
```bash
    cset shield -s -p  <PID>
```
where <PID> has to be substituted by the actual PID from the "timer-netsend-userspace-only" process. The userspace process runs now isolated on an own CPU
The maximum achivable packet rate can be observed by using "ecp3-ethtest-statreader.pl", the CPU utilisation can be recorded by using "poll_cpustatus.pl".

For testing the dependency of CPU utilisation to packet send rate the script "scripts/cpu_stress_control.sh" is started without parameters in parallel to the 
"userspace/timer-userspace-only" program. The sleep time might be selected for one case that a very low packet rate is send (eg. 5pps) and for a second case the 
maximum packet rate is send. 
The CPUSet creation and the transfer of the process needs to be performaed as descibed above.
The minimum, average and maximum inter packet delay can be observed with the "ecp3-ethtest-statreader.pl" script. 
The effective CPU utilisation can be recorded by using "poll_cpustatus.pl".
The data from CPU utilisation observation and the minimum, average and maximum inter packet delay will show the relation of CPU utilisation and ability to schedule packets for sending.

The CPUSet can be removed by giving 
```bash
    cset shield --reset
```
command.

## Setting up test processes on the tested plattform
 TBD


## Setting up load for tested plattform
 TBD


## FPGA board meassurment description
 TBD

## FPGA board configuration
 TBD

## Links
 http://www.falsig.org/simon/blog/2013/07/10/real-time-linux-kernel-drivers-part-3-the-better-implementation/
 
 
 

## Test description
### Userspace process only test
### Userspace sender process triggered by kernel
### Kernel module realtime scheduling and packet sending
### CPU sets with userspace process
  
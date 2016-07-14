#!/usr/bin/perl -w

use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(usleep nanosleep);
use Getopt::Std;
$|++; # autoflush buffers

my $send_buffer = "";
my $send_buffer_len = 20;

my %options=();
getopts("d:b:", \%options);

my $timer_delay = 1000000; # default 1 sec

if ($options{d}) {
    $timer_delay = $options{d};
}

if ($options{b}) {
    $send_buffer_len = $options{b};

}




if($timer_delay <1000) { die "less than 1 msec is no good idea\n"; }
 
if($send_buffer_len >1420) { die "MTU size is 1500 - IP (max size) - UDP = 1420, so please doent enter packet  size > 1420 \n"; }


for(my $i = 0; $i < $send_buffer_len; ++$i) {
    $send_buffer .= "x";
}
    
 
print $timer_delay."\n";



my @arp_list = `arp -n`;
chomp @arp_list;
my $arp_contains_target = 0;
my $run_udp_packet = 1;

$SIG{INT} = sub { $run_udp_packet = 0; };


foreach my $arp_line (@arp_list) { 					# checking for ARP entry presenese 
    if($arp_line =~/.*1\.1\.1\.2.*/ && $arp_line !~/.*incomplete.*/) { $arp_contains_target = 1; last; }
}


my $arp_set_return = -1;

if($arp_contains_target eq 0) { 					# if ARP entry not present try to set it
    print "ARP entry not present, setting IP 1.1.1.2 to  01:02:03:04:05:06\n";
    if(system("arp -s 1.1.1.2 01:02:03:04:05:06") ne 0) {
        die "could not set up ARP entry $?\n";
    }
}

my $sock = IO::Socket::INET->new(
    Proto    => 'udp',
    PeerPort => 1234,
    PeerHost => '1.1.1.2',
) or die "Could not create socket: $!\n";

print "\nloops forever and sends in 1 second period UDP packet to target\n";
print "    hit CTRL-C to terminate\n";

my $number_packet_sent = 0;
print "Sent packets: \033[s-";
while ($run_udp_packet) {
    ++$number_packet_sent;
    print "\033[u$number_packet_sent";
 
    $sock->send($send_buffer) or die "Send error: $!\n";
    usleep($timer_delay);
}
print "\ngot CTRL-C - exiting.\n";

$sock->close();




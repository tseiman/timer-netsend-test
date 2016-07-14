#!/usr/bin/perl -w

#
#	[[TBD - rights header]] (c) Thomas Schmidt, 2016
#	
#	This script reads measurement data from Lattice ECP3 Versa development board via FTDI/RS232.
#	
#	See README for more documentation
#
#	The ecp3-ethtest-statreader.pl script takes several command line parameters:
#	    -h              - help message and exit
#	    -v              - verbose loging to STDOUT, set as well when no CSV file given
#	    -f <FILENAME>   - log to this file in CSV format, if not given -v is automatically enabled
#	    -d <DEVICE>     - sets the tty serial device default is /dev/ttyUSB1
#	    -i <SEC>        - poll interval in seconds, default is 1 second
#




use strict;
use warnings;
use Device::SerialPort;
use Getopt::Std;
use IO::Handle;
$|++; # autoflush buffers


my %options=();
getopts("d:f:i:vh", \%options);


my $SERIAL_PORT = "/dev/ttyUSB1";

my $csv_file = "";
my $verbose = 0;
my $interval = 1;
my $fh;

if ($options{d}) {
    $SERIAL_PORT = $options{d};
}

if ($options{f}) {
    $csv_file = $options{f};
} else {
    undef $csv_file;
    $verbose = 1;
}

if ($options{v}) {
    $verbose = 1;
}

if ($options{i}) {
    $interval = $options{f};
}

if ($options{h}) {
    print "\n";
    print "  Reads Meassurement data from Lattice ECP3 Versa Card over RS232 (FTDI)\n";
    print "  Supported Parameters:\n";
    print "      -h              - this message\n";
    print "      -v              - verbose loging to STDOUT, set as well when no CSV file given\n";
    print "      -f <FILENAME>   - log to this file in CSV format, if not given -v is automatically enabled\n";
    print "      -d <DEVICE>     - sets the tty serial device (e.g. /dev/ttyUSB1)\n";
    print "      -i <SEC>        - poll interval in seconds, default 1\n\n";
    exit(0);
}



sub extractValue { 
    my($buffer,$offset,$len) = @_;
    
    
    my $result = 0;
    for(my $i = 0; $i < $len; ++$i) {
     my $shiftoffset = $i * 8;
     $result = $result + (ord(substr $buffer,$i + $offset,1) << ($i * 8));
    }
    return $result;
}




my $port = Device::SerialPort->new($SERIAL_PORT) || die "Can't open Serial Port ($SERIAL_PORT) $!\n";

$port->user_msg("ON");

$port->baudrate(38400); 
$port->databits(8); # but not this and the two following
$port->parity("none");
$port->stopbits(2);
$port->read_char_time(100);     # don't wait for each character
$port->read_const_time(1000); # 1 second per unfulfilled "read" call



$SIG{'INT'} = sub {
    print "\nExiting ...\n";
    if(defined $csv_file) { close $fh; }
    if(defined $port) { $port->close(); }
    exit(0);
};


if(defined $csv_file) {
    open($fh, '>>', $csv_file) or die "Could not open file '$csv_file' $!";    
    print $fh "Unix_Time,Total_Time,Received_Packets,PPS,Average_Interval,Max_Interval,Min_Interval,\n";
    $fh->autoflush;
}

my $poll_counter = 0;

my $unixtime = 0;

if(!$verbose) {
    print "Exit with CTRL-C, \033[s- polls done";
}

while(1) { # next poll loop
    ++$poll_counter;
    
    if(!$verbose) {
	print "\033[u$poll_counter polls done";
    }
    
    $port->write('G') or die "couldn't write control byte\n";

    my $buffer_in = "";

    while(1) {  # retry loop

	my $count_in = 0;
	($count_in, $buffer_in) =$port->read(17);
	if($count_in != 17) {
	    $port->write('R') or die "couldn't write control byte, retried to send control byte, cause bytes read was $count_in\n";
	    next;
	}

	my( $hex ) = unpack( 'H*', $buffer_in );
	if($verbose) { print "$hex\n"; }
	
	my $checksum_byte = ord(substr $buffer_in,16,1);

	my $checksum = 0;
	for(my $i = 0; $i < 16; ++$i) {
	    my $byte = ord(substr $buffer_in,$i,1);
	    if(($checksum + $byte) > 256) {
		$checksum = $checksum + $byte - 256;
	    } else {
		$checksum = $checksum + $byte;
	    }
	}

	if($checksum == $checksum_byte) {
	    last;
	} else {
	    $port->write('R') or warn "couldn't write control byte\n";
	}
    } # end retry loop

    $unixtime = time();

    my $sum =  extractValue($buffer_in,0,5);
    if($verbose) { 
	print "unixtime: $unixtime\n";
	printf "time sum: %u / %.8f\n",$sum, $sum / 125000000; 
    }

    my $count = extractValue($buffer_in,5,3);

    my $pps = 0;
    if( ($sum / 125000000) > 0) {
	$pps =  $count / ($sum / 125000000);
    }
    if($verbose) { 
	printf "packet/s: %.1f\n", $pps;
	printf "count: %u\n", $count;
    }

    my $avr = 0;

    if($count > 0) {
	$avr = $sum / $count/125000000;
    }
    my $min = (extractValue($buffer_in,8,4) /125000000);
    my $max =  (extractValue($buffer_in,12,4) /125000000);

    if($count < 2) { $min = 0; }

    
    if($verbose) { 
	printf "avg: %.8f\n", $avr;
	printf "min: %.8f\n", $min;
	printf "max: %.8f\n", $max;
    }

    if(defined $csv_file) {
#    print "\n";	
	print $fh "$unixtime,$sum,$count,$pps,$avr,$max,$min,\n";
    }

    
    sleep($interval);
} # end loop next poll


# never come here ...
if(defined $csv_file) { close $fh; }
$port->close();


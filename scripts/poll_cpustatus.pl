#!/usr/bin/perl -w

# stolen from here:
# https://gist.github.com/creaktive/781248
#
# Ref: Calculating CPU Usage from /proc/stat
# (http://colby.id.au/node/39)

use strict;
use warnings 'all';
use utf8;
use Getopt::Std;
use List::Util qw(sum);
use IO::Handle;

$| = 1;

my %options=();
getopts("f:i:h", \%options);


my $csv_file;
my $interval = 1;
my $fh;

my $preset_file = "/tmp/cpu_stress_control";


if ($options{f}) {
    $csv_file = $options{f};
} else {
    undef $csv_file;
}

if ($options{i}) {
    $interval = $options{i};
}


if ($options{h}) {
    print "\n";
    print "  Writes CPU usage either to stdout or if -f given with unix timestamp to CSV file\n";
    print "  Supported Parameters:\n";
    print "      -h              - this message\n";
    print "      -i <SEC>        - poll interval in seconds, default 1\n";
    print "      -f <FILENAME>   - log to this file in CSV format, if not given to STDOUT\n\n";
    exit(0);
}


if(defined $csv_file) {
    open($fh, '>>', $csv_file) or die "Could not open file '$csv_file' $!";    
    print $fh "Unix_Time,CPU_Usage,CPU_Preset,\n"
#    $fh->autoflush;
} else {
    print "Unix_Time,CPU_Usage,CPU_Preset,\n"
}

if(defined $csv_file) {
    print "Exit with CTRL-C, \033[s- polls done,  CPU is - %%";
}

$SIG{'INT'} = sub {
    if(defined $csv_file) {
	print "\nExiting ...\n";
    }
    if(defined $csv_file) { close $fh; }
    exit(0);
};


my $cpupreset = 0;
my $poll_counter = 0;
my ($prev_idle, $prev_total) = qw(0 0);
while () {
	++$poll_counter;
        open(STAT, '/proc/stat') or die "can't open /proc/stat ?!: $!";
        my $unixtime = time();

	if (-e "/tmp/cpu_stress_control") {
	    my $fh_preset;
	    open($fh_preset, '<', $preset_file) or die "Could not open file '$preset_file' $!";
    	    while (<$fh_preset>) {
		$cpupreset = $_;
	    }
	} else {
	    $cpupreset = 0;
	}

        while (<STAT>) {
                next unless /^cpu\s+[0-9]+/;
                my @cpu = split /\s+/, $_;
                shift @cpu;

                my $idle = $cpu[3];
                my $total = sum(@cpu);

                my $diff_idle = $idle - $prev_idle;
                my $diff_total = $total - $prev_total;
                my $diff_usage = 100 * ($diff_total - $diff_idle) / $diff_total;

                $prev_idle = $idle;
                $prev_total = $total;

		if(defined $csv_file) {
#            	    printf "CPU: %0.2f%%  \r", $diff_usage;
#            	    print "\033[u$poll_counter polls done";
		    printf "\033[u%lu polls done, CPU is %0.2f%%, preset is %0.2f%%",$poll_counter, $diff_usage, $cpupreset;
		    printf $fh "%lu,%0.2f,%0.2f,\n",$unixtime,$diff_usage, $cpupreset;

            	} else {
		    printf "%lu,%0.2f,%0.2f,\n",$unixtime,$diff_usage, $cpupreset;
            	}
        }
        close STAT;

        sleep $interval;
}
 
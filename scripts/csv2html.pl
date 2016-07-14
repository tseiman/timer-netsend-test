#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Date::Parse;

my $templatefile;
my $outfile;
my $inputfile;
my $eventfile;
my $headline;
my $ycaption;
my $now = localtime();


my $USAGE = "Usage: $0 --template <templatefile.html> --outfile <outfile.html> --inputfile <file.csv> --headline <headline>  --ycaption <y caption> --eventfile <eventfile>";


GetOptions(
   'template|t=s' => \$templatefile,
    'outfile|o=s' => \$outfile,
    'inputfile|i=s' => \$inputfile,
    'headline|h=s' => \$headline,
    'ycaption|y=s' => \$ycaption,
    'eventfile|e=s' => \$eventfile,
) or die "$USAGE\n";

if((! defined $templatefile) || (! defined $outfile) || (! defined $inputfile)  || (! defined $headline)  || (! defined $ycaption) ) {
	die "$USAGE\n";
}

if(defined $eventfile and (! -f $eventfile)) {
	die "eventfile defined - but not existing\n";
}


open(my $tfh, '<:encoding(UTF-8)', $templatefile) or die "Could not open file '$templatefile' $!\n";
open(my $ofh, '>:encoding(UTF-8)', $outfile) or die "Could not open file '$outfile' $!\n";


my $row;
while ($row = <$tfh>) {
	if($row =~m/.*Data1,Data2,Data3.*/ ) { last; }
	if($row =~m/.*<<GraphicTitle>>.*/ ) { $row =~ s/<<GraphicTitle>>/$headline/gi; }
	if($row =~m/.*<<GraphicYAxisTitle>>.*/ ) { $row =~ s/<<GraphicYAxisTitle>>/$ycaption/gi; }
	if($row =~m/.*<<DateNow>>.*/ ) { $row =~ s/<<DateNow>>/$now/gi; }
	if($row =~m/.*var annotations = ..;.*/ ) { 
		if(defined $eventfile and -f $eventfile) {

			open(my $ifh, '<:encoding(UTF-8)', $inputfile) or die "Could not open file '$inputfile' $!\n";
			my $event_line = <$ifh>;
			close($ifh);
			my @event_line = split(',',$event_line);	

			open(my $efh, '<:encoding(UTF-8)', $eventfile) or die "Could not open file '$eventfile' $!\n";
			$row = "var annotations = [\n";

			while (my $row_event = <$efh>) {
#				var annotations = [{ series: " CurReg:Active(O)",  x: "1436410930", shortText: "X", text: "Coldest Day", attachAtBottom: true, tickHeight: 430}];
					my @event_row_list = split(';',  $row_event);
					my $event_unixtime = str2time($event_row_list[0]);
					$row .=  "{ series: \"".$event_line[1]."\", x: \"".$event_unixtime."\", shortText: \"".$event_row_list[1]."\", text: \"".$event_row_list[2]."\", attachAtBottom: true, tickHeight: 430 },\n";
			}
			$row .= "];\n";			
			close($efh);
		}
	}
	print $ofh $row;
}

open(my $ifh, '<:encoding(UTF-8)', $inputfile) or die "Could not open file '$inputfile' $!\n";

print $ofh "\"";
while(my $line = <$ifh>) {
	$line =~s/\n/\\n/gi;
	print $ofh $line;
}
print $ofh "\",\n";

close($ifh);


while ($row = <$tfh>) {
	my $now = localtime();
	if($row =~m/.*<<GraphicTitle>>.*/ ) { $row =~ s/<<GraphicTitle>>/$headline/gi; }
	if($row =~m/.*<<GraphicYAxisTitle>>.*/ ) { $row =~ s/<<GraphicYAxisTitle>>/$ycaption/gi; }
	if($row =~m/.*<<DateNow>>.*/ ) { $row =~ s/<<DateNow>>/$now/gi; }
	if($row =~m/.*var annotations = ..;.*/ ) { 
		if(defined $eventfile and -f $eventfile) {

			open(my $ifh, '<:encoding(UTF-8)', $inputfile) or die "Could not open file '$inputfile' $!\n";
			my $event_line = <$ifh>;
			close($ifh);
			my @event_line = split(',',$event_line);	

			open(my $efh, '<:encoding(UTF-8)', $eventfile) or die "Could not open file '$eventfile' $!\n";
			$row = "var annotations = [\n";

			while (my $row_event = <$efh>) {
#				var annotations = [{ series: " CurReg:Active(O)",  x: "1436410930", shortText: "X", text: "Coldest Day", attachAtBottom: true, tickHeight: 430}];
					my @event_row_list = split(';',  $row_event);
					my $event_unixtime = str2time($event_row_list[0]);
					$row .=  "{ series: \"".$event_line[1]."\", x: \"".$event_unixtime."\", shortText: \"".$event_row_list[1]."\", text: \"".$event_row_list[2]."\", attachAtBottom: true, tickHeight: 430 },\n";
			}
			$row .= "];\n";			
			close($efh);
		}
	}
	print $ofh $row;
}

close($ofh);
close($tfh);


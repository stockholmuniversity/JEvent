#!/usr/bin/env perl

use Getopt::Std;
use JEvent;

my $usage=<<EOU;
Usage: $0 [-h] -c agent.ini

$0 Sample JEvent agent

SYNOPSIS

\t-c\tINI-style configuration file for this agent.
\t-h\tShow this text
\t-f\tCommand FIFO

EOU

getopts('c:hf:n:');
die $usage if $opt_h;
die $usage unless $opt_c;
die $usage unless -f $opt_c;
die $usage unless $opt_f;

$opt_n = 'rt' unless $opt_n;

my $ini = Config::IniFiles->new(-file=>$opt_c)
  or die "Unable to read configuration from $opt_c: $!\n";

my $host = Sys::Hostname::hostname();
my $FIFO = $opt_f;

$je = JEvent->new(Config=>$opt_c);
$je->Connect();

while (1) {
	unless (-p $FIFO) {
		unlink $FIFO;
		system('mknod',$FIFO,'p') 
			&& die "Unable to create $FIFO: $!";
	}
	open FIFO,"$FIFO" || die "Unable to open $FIFO for reading: $!";
	my $xml = <FIFO>;
	chomp $xml;
	close FIFO;	
	$je->Publish(Node=>$opt_n,Content=>$xml);
}

$je->Disconnect();
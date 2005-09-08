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

$je = JEvent->new(Config=>$ini);
$je->Connect();

while (1) {
	open FIFO,"$FIFO" || die "Unable to open $FIFO for reading: $!";
	local $_ = <FIFO>;
	chomp;
	close FIFO;	
	warn $_;
	my @entry = split /;/;
	my $fieldattr = " rt:field=\"$entry[1]\"" if $entry[1];
	my $xml=<<EOX;
<rt:rt xmlns:rt="http://resource.it.su.se/rt-jevent/NS/1.0/">
   <rt:txn rt:ticketId="$entry[0]"${fieldattr} rt:type="$entry[2]">
EOX
	$xml.=<<EOX if $entry[3];
      <rt:oldValue>$entry[3]</rt:oldValue>
EOX
	$xml.=<<EOX if $entry[4];
      <rt:newValue>$entry[4]</rt:newValue>
EOX
        $xml.=<<EOX;
      <rt:creator>$entry[5]</rt:creator>
      <rt:created>$entry[6]</rt:created>
   </rt:txn>
</rt:rt>
EOX
        warn $xml;
	my $msg = $je->Publish(Node=>$opt_n,Host=>'pubsub.cdr.su.se',Content=>$xml);
}

$je->Disconnect();

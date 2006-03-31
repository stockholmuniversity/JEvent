#!/usr/bin/env perl

use strict;
use JEvent;
use Net::CSTA;
use Getopt::Std;
use MIME::Base64;

use vars qw ($opt_c $opt_d $opt_h);

getopts('c:dh');

sub usage
{
    my $msg = shift || '';
    die (<<EOU);
${msg}Usage: $0 [-h] -c agent.ini

$0 CSTA JEvent agent

SYNOPSIS

\t-c\tINI-style configuration file for this agent.
\t-h\tShow this text
\t-d\tEnable debugging

EOU
}

usage () if ($opt_h);
usage ("Could not find config file '$opt_c'\n\n") if (! -f $opt_c);

my $debug = defined ($opt_d);
my %state;

my $ini = Config::IniFiles->new(-file => $opt_c)
    or die "Unable to read configuration from $opt_c: $!\n";
    
my $csta_server = $ini->val('CSTA','Server');
die "Missing [CSTA]Server from INI-file\n"
	unless $csta_server;

my $csta_port = $ini->val('CSTA','Port');
die "Missing [CSTA]Port from INI-file\n"
	unless $csta_port;

my @numbers = split(/\s*,\s*/,$ini->val('CSTA','Monitors'));

my $csta = Net::CSTA->new(Host=>$csta_server,Port=>$csta_port)
	or die "Unable to connect to CSTA server\n";

foreach (@numbers)
{
	my $result = $csta->request(serviceID => 71,
                                serviceArgs => {monitorObject=>{dialingNumber=>$_}});
}

my $je = JEvent->new(Config => $ini);

for (;;)
{
	my $req = $csta->receive();
	$req->{xmlns} = 'http://resource.it.su.se/CSTA/1.0';
	$je->Publish(Content=>$req->toXML());
}

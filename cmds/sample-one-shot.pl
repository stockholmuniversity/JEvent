#!/usr/bin/env perl

use JEvent;
use Config::IniFiles;

my $ini =  Config::IniFiles->new(-file=>$ENV{JEVENTINI} || '/etc/jevent.ini');
my $je = JEvent->new(Config => $ini)
      or die "Unable to create JEvent interface";

$je->Connect();

my $node = "/some/random/node";
my $content = "<some random=\"1\"><data/></some>\n";

my $msg = $je->Publish(Node=>$node,Content=>$content);

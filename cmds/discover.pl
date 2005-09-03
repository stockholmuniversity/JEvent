#!/usr/bin/env perl

use JEvent;
use Config::IniFiles;

my $ini = Config::IniFiles->new(-file=>$ENV{JEVENTINI})
  or die "Unable to read $ENV{JEVENTINI}\n";


my $je = JEvent->new(Config => $ini);
my $msg = $je->Run(sub { $_[0]->DiscoverNodes(Node=>$ARGV[1],Host=>$ARGV[0]) });
warn $msg->GetXML();
my $query = $msg->GetQuery('http://jabber.org/protocol/disco#items');
foreach my $item ($query->GetItem())
  {
    printf "%s %s\n",$item->GetJID(),$item->GetNode();
  }


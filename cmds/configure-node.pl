#!/usr/bin/env perl

use JEvent;
use CGI;
use Config::IniFiles;

my $ini = Config::IniFiles->new(-file=>$ENV{JEVENTINI})
  or die "Unable to read $ENV{JEVENTINI}\n";


my $je = JEvent->new(Config => $ini);
$je->Connect();
my $msg = $je->ConfigureNode(Host=>$ARGV[0],Node=>$ARGV[1]);
my $iq = $msg->GetChild('http://jabber.org/protocol/pubsub#owner');
my $configure = $iq->GetConfigure();
my $form = $configure->GetForm();
#warn $form->GetXML();
$je->FormHTML($form,CGI->new());

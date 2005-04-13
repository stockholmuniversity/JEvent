# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 1 };
use JEvent;
ok(1); # If we made it this far, we're ok.

my $host = 'localhost';

my $je = JEvent->new(JID=>"app2\@$host/JEvent",
		     Password=>'app2',
		     EventCB =>sub {
		       my ($je,$sid,$msg) = @_;
		       warn "Event\n";
		       warn $msg->GetXML();
		     },
		     Commands=>{
				publish => sub {
				  my ($self,$from,$type,$cmd,@args) = @_;
				  warn "publish: $self $cmd @args\n";
				  my $data = join('',map { "<data>$_</data>" } @args);
				  my $result = $self->Publish(Host=>"pubsub.$host",
							      Node=>"home/$host/admin/test",
							      Content=>"<command name=\"$cmd\">$data</command>");
				  $result->GetErrorCode ? $result->GetErrorCode: "Success";
				}
			       });
ok(2);
$je->Run(Data=>\*STDIN,Subscribe=>[
				   {
				    Host => "pubsub.$host",
				    Node => 'home/localhost/admin/test'
				   }
				  ]);
ok(3);

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.


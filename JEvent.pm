package JEvent;

use 5.006;
use strict;
use warnings;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use JEvent ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);
our $VERSION = '0.11';

use Net::XMPP qw(Client);
use Net::XMPP::JID;
use Data::UUID;
use Net::SPOCP;
use Sys::Syslog qw(:DEFAULT);
use Config::IniFiles;

sub new
  {
    my $self = shift;
    my $class = ref $self || $self;

    my %me = @_;
    $me{Config} = Config::IniFiles->new() unless UNIVERSAL::isa($me{Config},'Config::IniFiles');

    my $this = bless \%me,$class;
    $this->init();
  }

sub LogWarn
  {
    my($self,$msg,@args) = @_;

    syslog('warning',$msg,@args);
  }

sub LogError
  {
    my($self,$msg,@args) = @_;

    syslog('error',$msg,@args);
  }

sub LogInfo
  {
    my($self,$msg,@args) = @_;

    syslog('info',$msg,@args);
  }

sub LogDebug
  {
    my($self,$msg,@args) = @_;

    syslog('debug',$msg,@args);
  }

sub Client
  {
    $_[0]->{_xmpp};
  }

sub JID
  {
    $_[0]->{_jid}
  }

sub Hostname
  {
    $_[0]->JID->GetServer();
  }

sub Username
  {
    $_[0]->JID->GetUserID();
  }

sub Resource
  {
    $_[0]->JID->GetResource();
  }

sub Password
  {
    my $pw = $_[0]->{Password};
    return $pw if $pw;
    &{$_[0]->{PasswordCB}}($_[0]) if ref $_[0]->{PasswordCB};
    die "Missing Password and/or PasswordCB\n";
  }

sub cfg
  {
    my $self = shift;
    $self->{_cfg}->val(@_);
  }

sub init
  {
    my $self = shift;

    openlog "JEvent $0","pid",'LOG_USER';

    $self->{_jid} = Net::XMPP::JID->new($self->{JID} || $self->cfg('JEvent','JID'));
    $self->{Timeout} = $self->cfg('JEvent','Timeout') unless $self->{Timeout}
    $self->{Timeout} = 5 unless $self->{Timeout};
    $self->{Password} = $self->cfg('JEvent','Password') unless $self->{Password};
    $self->{_ug} = Data::UUID->new();

    my @opts = ();
    $self->{DebugLevel} = $self->cfg('JEvent','DebugLevel') unless $self->{DebugLevel};
    $self->{DebugFile} = $self->cfg('JEvent','DebugFile') unless $self->{DebugFile};
    push(@opts,debuglevel=>$self->{DebugLevel}) if $self->{DebugLevel};
    push(@opts,debugfile=>$self->{DebugFile}) if $self->{DebugFile};

    $self->{Host} = $self->cfg('PubSub','Host') unless $self->{Host};
    $self->{Node} = $self->cfg('PubSub','Node') unless $self->{Node};
    $self->{Description} = $self->cfg('JEvent','Description') unless $self->{Description};

    $self->{SPOCPServer} = $self->cfg('SPOCP','Server') unless $self->{SPOCPServer};
    $self->{UseTLS} = $self->cfg('JEvent','UseTLS') unless $self->{UseTLS};
    $self->{SSLVerify} = $self->cfg('SSL','verify') unless $self->{SSLVerify};
    $self->{CAFile} = $self->cfg('SSL','cafile') unless $self->{CAFile};
    $self->{CADir} = $self->cfg('SSL','cadir') unless $self->{CADir};
    $self->{ProcessTimeout} = $self->cfg('JEvent','ProcessTimeout');

    $self->{_xmpp} = Net::XMPP::Client->new(@opts);
    $self->Client->SetCallBacks(onauth=>sub
				 {
				   $self->Client->PresenceSend();
				   &{$self->{StartCB}}($self) if ref $self->{StartCB} eq 'CODE';
				 },
				 onprocess=>sub
				 {
				   &{$self->{ProcessCB}}($self) if ref $self->{ProcessCB} eq 'CODE';
				 });

    $self->Client->SetMessageCallBacks(error=>sub
					{
					  #warn $_[1]->GetXML();
					},
					groupchat=>sub
					{
					  &{$self->{MessageCB}}($self,@_) if ref $self->{MessageCB} eq 'CODE';
					},
					normal=>sub
					{
					  &{$self->{MessageCB}}($self,@_) if ref $self->{MessageCB} eq 'CODE';
					},
					chat=>sub
					{
					  &{$self->{MessageCB}}($self,@_) if ref $self->{MessageCB} eq 'CODE';
					});

    $self->Client->SetPresenceCallBacks(subscribe => sub {
					   my $ok = ref $self->{SubscriptionAuthorization} eq 'CODE' ?
					     &{$self->{SubscriptionAuthorization}}($self,@_) : 1;
					   if ($ok)
					     {
					       $self->PresenceSend({to=>$_[1]->GetFrom(),type=>'subscribed'});
					     }
					   else
					     {
					       $self->PresenceSend({to=>$_[1]->GetFrom(),type=>'unsubscribed'});
					     }
					 });

    $self->Client->SetXPathCallBacks("/message/event[\@xmlns=\'http://jabber.org/protocol/pubsub#event\']" => sub
				      {
					&{$self->{EventCB}}($self,@_) if ref $self->{EventCB} eq 'CODE';
				      });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/pubsub',
				 tag=>'pubsub',
				 xpath=>{
					 Publish => { calls => [qw/Get Add Defined/],
						      type => 'child',
						      path => 'publish',
						      child => { ns => '__netxmpp__:pubsub:publish' } },

					 Retract => { calls => [qw/Get Add Defined/],
						      type => 'child',
						      path => 'retract',
						      child => { ns => '__netxmpp__:pubsub:retract' } },

					 Subscribe => { calls => [qw/Get Add Defined/],
							type => 'child',
							path => 'subscribe',
							child => { ns => '__netxmpp__:pubsub:subscribe' } },

					 Unsubscribe => { calls => [qw/Get Add Defined/],
							  type => 'child',
							  path => 'unsubscribe',
							  child => { ns => '__netxmpp__:pubsub:unsubscribe' } },

					 Entity => { calls => [qw/Get Add Defined/],
						     type => 'child',
						     path => 'entity',
						     child => { ns => '__netxmpp__:pubsub:entity' } },

					 Affiliations => { calls => [qw/Get Add Defined/],
							   type => 'child',
							   path => 'affiliations',
							   child => { ns => '__netxmpp__:pubsub:affiliations' } },
					
					 Items => { calls => [qw/Get Set/],
						    type => 'child',
						    path => 'items',
						    child => { ns => '__netxmpp__:pubsub:items' } },
					},
				);

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:publish',
				 tag => 'publish',
				 xpath=>{
					 Node => { path => '@node' },
					 Item => { calls => [qw/Get Set/],
						   type => 'child',
						   path => 'item',
						   child => { ns => '__netxmpp__:pubsub:publish:item' } }

					},
				);

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:retract',
				 tag => 'publish',
				 xpath=>{
					 Node => { path => '@node' },

					 Item => { calls => [qw/Get Set/],
						   type => 'child',
						   path => 'item',
						   child => { ns => '__netxmpp__:pubsub:retract:item' } }

					},
				);

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:publish:item',
				 tag => 'item',
				 xpath=>{
					 Id => { path => '@id' },
					 Content => { type => 'raw', path => '.' }
					});

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:retract:item',
				 tag => 'item',
				 xpath=>{
					 Id => { path => '@id' },
					});

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:subscribe',
				 tag => 'subscribe',
				 xpath=>{
					 Node => { path => '@node' },
					 SubID => { path => '@subid' },
					 JID => { type => 'jid', path => '@jid' }
					});

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:unsubscribe',
				 tag => 'unsubscribe',
				 xpath=>{
					 Node => { path => '@node' },
					 JID => { type => 'jid', path => '@jid' },
					 SubID => { path => '@subid' }
					});

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:entity',
				 tag => 'entity',
				 xpath=>{
					 Node => { path => '@node' },
					 JID => { type => 'jid', path => '@jid' },
					 Affiliation => { path => '@affiliation' },
					 SubID => { path => '@subid' },
					 Subscription => { path => '@subscribed' }
					});

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:affiliations',
				 tag => 'affiliations',
				 xpath => {
					   Entity => { calls => [qw/Get Add Defined/],
						       type => 'child',
						       path => 'entity',
						       child => { ns => '__netxmpp__:pubsub:entity' } }
					  });

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:items',
				 tag => 'items',
				 xpath=>{
					 Node => { path => '@node' },
					 JID => { type => 'jid' },
					 SubID => { path => '@subid' },
					 MaxItems => { path => '@max_items' },
					 Item => { calls => [ qw/Add/],
						   type => 'child',
						   path => 'item',
						   child => { ns => '__netxmpp__:pubsub:item' } },
					 Items => { calls => [ qw/Get/],
						    type => 'child',
						    path => 'item',
						    child => { ns => '__netxmpp__:pubsub:item' } }
					});

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/pubsub#event',
				 tag => 'event',
				 xpath => {
					   Items => { calls => [ qw/Get Add/],
						      type => 'child',
						      path => 'items',
						      child => { ns => '__netxmpp__:pubsub:items' } }
					  });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/muc',
				 tag => 'x',
				 xpath => {
					   Password => { path => '@password' }
					  });

    $self->Client->AddNamespace(ns=>'jabber:x:conference',
				 tag => 'x',
				 xpath => {
					   JID => { path => '@jid', type => 'jid' }
					  });

    $self;
  }

sub Subscribe
  {
    my $self = shift;
    my %opts = @_;

    my $iq = Net::XMPP::IQ->new();
    $iq->SetIQ(type=>'set',
	       from=>$self->JID,
	       to=>$opts{Host} || $self->Hostname);

    my $pubsub = $iq->NewChild("http://jabber.org/protocol/pubsub");
    my $subscribe = $pubsub->AddSubscribe();
    $subscribe->SetNode($opts{Node});
    $subscribe->SetJID($opts{JID} || $self->JID);
    $subscribe->SetSubID($opts{SubID}) if $opts{SubID};

    #warn $iq->GetXML();
    my $msg = $self->Client->SendAndReceiveWithID($iq,$self->{Timeout});
    #warn $msg->GetXML() if $msg;
    $msg;
  }

sub Unsubscribe
  {
    my $self = shift;
    my %opts = @_;

    my $iq = Net::XMPP::IQ->new();
    $iq->SetIQ(type=>'set',
	       from=>$self->JID,
	       to=>$opts{Host} || $self->Hostname);

    my $pubsub = $iq->NewChild("http://jabber.org/protocol/pubsub");
    my $subscribe = $pubsub->AddUnsubscribe();
    $subscribe->SetNode($opts{Node});
    $subscribe->SetJID($opts{JID} || $self->JID);
    $subscribe->SetSubID($opts{SubID}) if $opts{SubID};

    #warn $iq->GetXML();
    my $msg = $self->Client->SendAndReceiveWithID($iq,$self->{Timeout});
    #warn $msg->GetXML() if $msg;
    $msg;
  }

sub Publish
  {
    my $self = shift;
    my %opts = @_;

    my $iq = Net::XMPP::IQ->new();
    $iq->SetIQ(type=>'set',
	       from=>$self->JID,
	       to=>$opts{Host} || $self->cfg('PubSub','Host') || $self->Hostname);

    my $pubsub = $iq->NewChild("http://jabber.org/protocol/pubsub");
    my $publish = $pubsub->AddPublish();
    $publish->SetNode($opts{Node} || $self->cfg('PubSub','Node'));
    my $item = $publish->AddItem();
    $item->SetId(defined $opts{Id} ? $opts{Id} : $self->{_ug}->create_str());
    $item->SetContent($opts{Content});

    #warn $iq->GetXML();
    my $msg = $self->Client->SendAndReceiveWithID($iq,$self->{Timeout});
    #warn $msg->GetXML() if $msg;
    $msg;
  }

sub initSubscriptions
  {
    my $self = shift;

    if (ref $self->{Subscribe} eq 'ARRAY')
      {
	foreach my $s (@{$self->{Subscribe}})
	  {
	    $self->Subscribe($s->{Host},$s->{Node})
	  }
      }
  }

sub Usage
  {
    my $uid = $_[0]->Username;
    $_[0]->{Description} || "Hello I am $uid";
  }

sub evalCommand
  {
    my ($self,$sid,$msg) = @_;

    my $type = $msg->GetType();
    my $body = $msg->GetBody();

    if ($type eq 'groupchat')
      {
	my $tag;

	return undef unless ($tag) = $body =~ /^\s*(\S+):\s+/o;
	return undef unless $tag eq $self->Username || $tag eq $self->JID->GetJID("base");
      }
    else
      {
	if ($msg->DefinedChild("jabber:x:conference"))
	  {
	    my $x = $msg->GetChild("jabber:x:conference");
	    my $room_jid = Net::XMPP::JID->new($x->GetJID()) if $x;
	    if ($room_jid)
	      {
		my $presence = Net::XMPP::Presence->new();
		$presence->SetPresence(To=>$room_jid->GetJID("base")."/".$self->Username,
				       From=>$self->JID->GetJID());
		$presence->NewChild("http://jabber.org/protocol/muc");
		my $result = $self->Client->SendAndReceiveWithID($presence,$self->{Timeout});
		if ($result->GetErrorCode())
		  {
		    #warn $result->GetXML();
		    return undef;
		  }

		$self->{_rooms}->{$room_jid}++;
		return $self->Client->MessageSend(from=>$self->JID->GetJID("base"),
						  to=>$room_jid->GetJID("base"),
						  type=>'groupchat',
						  body=>$self->Usage());
	      }
	  }
      }

    my $from = Net::XMPP::JID->new($msg->GetFrom());

    return $self->Client->MessageSend(to=>$from->GetJID("base"),
				       type=>$type,
				       body=>"I have no commands configured.\n")
      unless ref $self->{Commands} eq 'HASH';

    my ($cmd,$args);

    return $self->Client->MessageSend(to=>$from->GetJID("base"),
				      type=>$type,
				      body=>"I don't understand this: \"$body\"")
      unless ($cmd,$args) = $body =~ /^\s*(\S+)\s*(.*)\s*$/o;

    my @args = split /\s+/,$args;

  BUILTIN:
    {
      $cmd eq '?' || $cmd eq 'help' || $cmd eq 'who' and do {

	my $body = $self->Usage."\nCommands: \n";
	foreach my $c (keys %{$self->{Commands}})
	  {
	    $body .= "$c\n";
	  }
	return $self->Client->MessageSend(to=>$from->GetJID("base"),
					  type=>$type,
					  body=>$body);
      },last BUILTIN;
    }


    if (ref $self->{Commands}->{$cmd} eq 'CODE')
      {
	if (ref $self->{CommandAuthorization} eq 'CODE')
	  {
	    return $self->Client->MessageSend(to=>$from->GetJID("base"),
					      type=>$type,
					      body=>'Not authorized')
	      unless &{$self->{CommandAuthorization}}($self,$from->GetJID("base"),$type,$cmd,@args);
		
	  }
	
	my $result = &{$self->{Commands}->{$cmd}}($self,$from->GetJID("base"),$type,$cmd,@args);

	return $self->Client->MessageSend(to=>$from->GetJID("base"),
					  type=>$type,
					  body=>$result) if $result;
      }
    else
      {
	return $self->Client->MessageSend(to=>$from->GetJID("base"),
					  type=>$type,
					  body=>"No such command: \"$cmd\"")
      }
  }

sub spocpCommandAuthorization
  {
    my ($self,$from,$cmd,@args) = @_;

    my $spocp = Net::SPOCP::Client->new(server=>$self->{SPOCPServer});
    my $to = $self->JID->GetJID("base");
    my $res = $spocp->query([jevent => [command => $cmd],[from => $from],[to => $to]]);
    return !$res->is_error;
  }

sub spocpSubscriptionAuthorization
  {
    my ($self,$sid,$msg) = @_;

    my $spocp = Net::SPOCP::Client->new(server=>$self->{SPOCPServer});
    my $to = $self->JID->GetJID("base");
    my $from = Net::XMPP::JID->new($msg->GetFrom())->GetJID("base");
    my $res = $spocp->query([jevent => [method => 'subcribe'],[from => $from],[to => $to]]);
    return !$res->is_error;
  }

sub PreExecute() { }

sub Run
  {
    my $self = shift;
    my %opts = @_;

    $self->{Subscribe} = $opts{Subscribe} if ref $opts{Subscribe};
    $self->{StartCB} = \&initSubscriptions unless ref $self->{StartCB} eq 'CODE';
    $self->{MessageCB} = \&evalCommand unless ref $self->{MessageCB} eq 'CODE';
    $self->{CommandAuthorization} = \&spocpCommandAuthorization
      unless ref $self->{CommandAuthorization} eq 'CODE';
    $self->{SubscriptionAuthorization} = \&spocpSubscriptionAuthorization
      unless ref $self->{SubscriptionAuthorization} eq 'CODE';
    $self->{Data} = $opts{Data} if $opts{Data};

    $self->PreExecute();

    $self->Client->Execute(hostname=>$self->Hostname,
			   username=>$self->Username,
			   password=>$self->Password,
			   tls=>$self->{UseTLS},
			   tlsoptions=>{
					SSL_verify_mode=>$self->{SSLVerify}||0x01 , #require
					SSL_ca_file=>$self->{CAFile}||'/etc/ssl/ca.crt',
					SSL_ca_dir=>$self->{CADir}
				       },
			   resource=>$self->Resource,
			   processtimeout=>$self->{ProcessTimeout} || 1,
			   register=>0);
  }


# Preloaded methods go here.
# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

JEvent - An eventdriven framework for XMPP PubSub

=head1 SYNOPSIS

  use JEvent;

  my $je = JEvent->new(JID=>'app@localhost',
                       Password => 'secret',
                       Commands=> { hello => sub { "hello ".$_[1] } },
                       ProcessTimeout => 10,
                       ProcessCB => sub {
                          my $now = localtime;
                          $_[0]->Publish(Host=>'pubsub.localhost',
                                         Node=>'a/pubsub/node',
                                         Content=>"<date>$now</date>");
                       });

  $je->Run();


This script will publish the date at 'a/pubsub/node@pubsub.localhost' every
10 seconds. If you send the string 'hello' using a normal or chat XMPP message
to the JID (app@localhost) or 'app: hello' in a multiuser chat room the agent
will respond with 'hello ' followed by the JID of the sender.

=head1 DESCRIPTION

JEvent is a wrapper class around Net::XMPP which also implements parts of
PubSub (JEP0060). The purpouse of JEvent is to create a framework for building
agents capable of publishing and consuming events. JEvent also supports a
simple mechanism of management by sending text-commands to the agent. Typically
an agent is implemented as a perl-script which creates a JEvent object and 
calls the Run method.

Method calls are authorized using calls to a SPOCP server. This behaviour can
be overridden by providing the CommandAuthorization argument to the JEvent
constructor.

=head1 CONSTRUCTOR

 my $je = JEvent::new(
      Argument => Value,

      ...
    );

 Argument            Description
 -----------------------------------------------------------------------

 JID                  The JID to run the agent as.

 Password             Authentication for this JID.

 Commands             A HASH reference keyed with names of commands.
                      Values are CODE references. Each command is called
                      with the JEvent object, the sender JID (Net::XMPP::JID)
                      the message type, the command name, and the arguments.
                      The return value from the function is sent to the sender
                      using the same type of message as the incoming message.
                      Each command call is authorized (see AUTHORIZATION).

 Timeout              Timeouts for various actions.

 StartCB              This CODE is run everytime the agent authenticates
                      to the server. Normally you don't override this. If
                      you do you must handle your initial Subscriptions
                      manually.

 MessageCB            This CODE is run for each incoming message. If you
                      override this you cannot implement Commands.

 ProcessCB            This CODE is run every ProcessTimeout seconds and is
                      where your agent can originate events.

 EventCB              This CODE is run whenever a pubsub event is received
                      and is called with the JEvent object, the XMPP
                      session id (sid) and the Net::XMPP::Message object.
                      If your agent is subscribing to PubSub nodes this is
                      where your consumer code lives.

 SPOCPServer          The <hostname:port> of the SPOCP authorization server.

 CommandAuthorization Override (CODE) the way commands are authorized. The
                      CODE is called with the same arguments that Commands
                      are called with.

 Subscribe            An reference to an ARRAY of HASH references describing
                      initial subscriptions. Must contain a 'Node' and a
                      Host key. The Host value is the hostname of the pubsub
                      service. Note that you only have to subscribe to a node
                      once. Using this feature is overkill.

 Usage                A text-description of this agent.

=head1 AUTHORIZATION

Method calls are authorized using calls to a SPOCP server. This behaviour can
be overridden by providing the CommandAuthorization argument to the JEvent
constructor. By default the SPOCPServer (<hostname:port>) is used to convey
information about the SPOCP server.

The S-Expressions used are of the following form:

 (jevent (command $command) (from $from_jid) (to $to_jid))

By creating a rule of the form

 (jevent (command foo) (from) (to))

anyone can use the command 'foo'. Consult your SPOCP documentation for
further details.

When the agent receives a subscription request the following rule is
use to authorize it:

 (jevent (method subscribe) (from $from_jid) (to $to_jid))

=head1 METHODS

$je->Publish(Host    => $pubsub_hostname,
             Node    => $pubsub_node,
             Content => $xml_text);

$je->Subscribe(Host  => $pubsub_hostname,
               Node  => $pubsub_node,
               SubID => $subid,
               JID   => $jid_to_subscribe_as);

$je->Unsubscribe(Host  => $pubsub_hostname,
                 Node  => $pubsub_node,
                 SubID => $subid,
                 JID   => $jid_to_subscribe_as);

$je->LogWarn($format,@args);
$je->LogError($format,@args);
$je->LogInfo($format,@args);
$je->LogDebug($format,@args);

Log messages to syslog with the relevant priority.

$je->Client

Access the underlying Net::XMPP::Client object. This can be used
to send an receive messages as a regular XMPP client would.

=head1 AUTHOR

Leif Johansson <leifj@it.su.se>

=head1 SEE ALSO

L<perl>. L<Net::XMPP>, L<Net::SPOCP>

=head1 BUGS

JEvent does not authorize subscription requests.

=cut

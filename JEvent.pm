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
our $VERSION = '0.13';

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
    $me{Config} = Config::IniFiles->new(-file=>$ENV{JEVENTINI} || '/etc/jevent.ini')
       unless UNIVERSAL::isa($me{Config},'Config::IniFiles');

    my $this = bless \%me,$class;
    $this->init();
  }

sub DESTROY
  {
    eval { $_[0]->Disconnect(); };
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
    $self->{Config}->val(@_);
  }

sub gen_uuid
  {
    $_[0]->{_ug}->create_str();
  }

sub init
  {
    my $self = shift;

    openlog "JEvent $0","pid",'LOG_USER';

    $self->{_jid} = Net::XMPP::JID->new($self->{JID} || $self->cfg('JEvent','JID'));
    $self->{Timeout} = $self->cfg('JEvent','Timeout') unless $self->{Timeout};
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
    my $h = $self->cfg('JEvent','Handles') || '';
    foreach my $handle (split /\s*,\s*/,$h) {
       $self->addHandle($handle);
    }

    $self->{_xmpp} = Net::XMPP::Client->new(@opts);
    $self->Client->SetCallBacks(onauth=>sub {
				   $self->Client->PresenceSend();
				   &{$self->{StartCB}}($self) if ref $self->{StartCB} eq 'CODE';
				 },
				 onprocess=>sub {
				   &{$self->{ProcessCB}}($self) if ref $self->{ProcessCB} eq 'CODE';
				 },
                                 presence=>sub {
                                   my ($sid,$msg) = @_;
                                   if ($msg->GetType() eq 'subscribe') {
                                       my $ok = ref $self->{SubscriptionAuthorization} eq 'CODE' ?
                                          &{$self->{SubscriptionAuthorization}}($self,@_) : 1;
                                       if ($ok) {
                                          $self->Client->PresenceSend(to=>$_[1]->GetFrom(),type=>'subscribed');
                                       } else {
                                          $self->Client->PresenceSend(to=>$_[1]->GetFrom(),type=>'unsubscribed');
                                       }  
                                   } else {
                                       warn $msg->GetXML();
                                       &{$self->{PresenceCB}}($self,@_) if ref $self->{PresenceCB} eq 'CODE';
                                   }
                                 }
                               );

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

    $self->Client->SetXPathCallBacks("/message/event[\@xmlns=\'http://jabber.org/protocol/pubsub#event\']" => sub
				      {
					&{$self->{EventCB}}($self,$_[0],$_[1]->GetChild('http://jabber.org/protocol/pubsub#event')) if ref $self->{EventCB} eq 'CODE';
				      });
    
    $self->Client->SetXPathCallBacks("/message/x[\@xmlns=\'http://jabber.org/protocol/pubsub#event\']" => sub
                                      {
                                        &{$self->{EventCB}}($self,$_[0],$_[1]->GetChild('http://jabber.org/protocol/pubsub#event')) if ref $self->{EventCB} eq 'CODE';
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

					 Create => { calls => [qw/Get Add Defined/],
					             type => 'child',
					             path => 'create',
						     child => { ns => '__netxmpp__:pubsub:create' } },
					
					 Delete => { calls => [qw/Get Add Defined/],
                                                     type => 'child',
                                                     path => 'delete',
                                                     child => { ns => '__netxmpp__:pubsub:delete' } },

                                         Purge => { calls => [qw/Get Add Defined/],
						    type => 'child',
						    path => 'purge',
						    child => { ns => '__netxmpp__:pubsub:purge' } },

                                         Entities => { calls => [qw/Get Add Defined/],
						       type => 'child',
						       path => 'entities',
						       child => { ns => '__netxmpp__:pubsub:entities' } },

					 Items => { calls => [qw/Get Add Set/],
						    type => 'child',
						    path => 'items',
						    child => { ns => '__netxmpp__:pubsub:items' } },
					},
				);

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:publish',
				 tag => 'publish',
				 xpath=>{
					 Node => { path => '@node' },
					 Item => { calls => [qw/Get Set Add/],
						   type => 'child',
						   path => 'item',
						   child => { ns => '__netxmpp__:pubsub:publish:item' } }

					},
				);

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:create',
                                tag => 'create',
                                xpath => {
                                          Node => { path => '@node' }
                                         }
                                );

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:delete',
                                tag => 'delete',
                                xpath => {
                                          Node => { path => '@node' }
                                         }
                                );

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:purge',
                                tag => 'purge',
                                xpath => {
                                          Node => { path => '@node' }
                                         }
                                );

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:entities',
                                tag => 'entities',
                                xpath => {
                                          Node => { path => '@node' },
					  Entity => { calls => [qw/Get Set Add/],
					              type => 'child',
						      path => 'entity',
						      child => { ns => '__netxmpp__:pubsub:entity' } }
                                         }
                                );

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:retract',
				 tag => 'retract',
				 xpath=>{
					 Node => { path => '@node' },
					 Item => { calls => [qw/Get Add Set/],
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
					 Subscription => { path => '@subscription' },
                                         Subscribed => { path => '@subscribed' }
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
						  child => { ns => '__netxmpp__:pubsub:publish:item' } },
					Items => { calls => [ qw/Get/],
						   type => 'child',
						   path => 'item',
						   child => { ns => '__netxmpp__:pubsub:publish:item' } }
				       });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/pubsub#owner',
				tag => 'pubsub',
				xpath => {
					  Configure => { calls => [ qw/Get Add/],
							 type => 'child',
							 path => 'configure',
							 child => { ns => '__netxmpp__:pubsub:owner:configure' } }
					 });

    $self->Client->AddNamespace(ns=>'__netxmpp__:pubsub:owner:configure',
				tag => 'configure',
				xpath => {
					  Node => { path => '@node' },
					  Form => { calls => [ qw /Get Add Defined/ ],
						    type => 'child',
						    path => 'x',
						    child => { ns => 'jabber:x:data' } }
					 });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/pubsub#event',
				tag => 'event',
				xpath => {
					  Items => { calls => [ qw/Get Add/],
						     type => 'child',
						     path => 'items',
						     child => { ns => '__netxmpp__:pubsub:items' } },
					  Delete => { calls => [ qw/Get Add/],
						      type => 'child',
						      path => 'delete',
						      child => { ns => '__netxmpp__:pubsub:delete' } },
					  Purge => { calls => [ qw/Get Add/],
						     type => 'child',
						     path => 'purge',
						     child => { ns => '__netxmpp__:pubsub:purge' } }
					 });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/pubsub#event',
				tag=>'pubsub',
				xpath => {
					  Items => { calls => [ qw/Get Add/],
						     type => 'child',
						     path => 'items',
						     child => { ns => '__netxmpp__:pubsub:items' } },
					  Affiliations => { calls => [ qw/Get Add/ ],
							    type => 'child',
							    path => 'affiliations',
							    child => { ns => '__netxmpp__:pubsub:affiliations' } },
					  Entities => { calls => [qw/Get Add Defined/],
							type => 'child',
							path => 'entities',
							child => { ns => '__netxmpp__:pubsub:entities' } }
					 });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/muc',
				 tag => 'x',
				 xpath => {
					   Password => { path => '@password' },
					   Form => { calls => [ qw/Set Defined Get/ ],
						     type => 'child',
						     path => 'x',
						     child => { ns => 'jabber:x:data' } }
					  });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/muc#user',
	                        tag => 'x',
	                        xpath => {
                                           Item => { calls => [ qw/Get Add/ ],
						     type => 'child',
						     path => 'item',
					             child => { ns=> '__netxmpp__:muc:user:item' }
                                                   }
                                         });

    $self->Client->AddNamespace(ns=>'__netxmpp__:muc:user:item',
			        tag => 'item',
                                xpath => {
                                            Affiliation=> { path => '@affiliation' },
                                            Role => { path => '@role' },
			                    JID => { type => 'jid', path => '@jid' }
                                         });

    $self->Client->AddNamespace(ns=>'jabber:x:conference',
				 tag => 'x',
				 xpath => {
					   JID => { path => '@jid', type => 'jid' }
					  });

    $self->Client->AddNamespace(ns=>'http://jevent.it.su.se/NS/command',
				tag => 'command',
				xpath => {
					  Form => { calls => [ qw/Set Defined Get/ ],
						    type  => 'child',
						    path  => 'x',
						    child => { ns => 'jabber:x:data' } }
					 });

    $self->Client->AddNamespace(ns=>'jabber:x:data',
                                tag=>'x',
                                xpath => {
                                           Type => { path => '@type' },
                                           Title => { path => 'title/text()' },
                                           Instructions => { path => 'instructions/text()' },
                                           Field => { calls => [ qw/Get Add/ ],
                                                      type => 'child',
                                                      path => 'field',
                                                      child => { ns => '__netxmpp__:form:field' } }
                                         });

    $self->Client->AddNamespace(ns=>'__netxmpp__:form:field',
                                tag=>'field',
                                xpath => {
					  Type => { path => '@type' },
					  Label => { path => '@label' },
					  Var => { path => '@var' },
                                          Value => { calls => [ qw/Get Add/ ],
                                                     type => 'child',
                                                     path => 'value',
                                                     child => { ns => '__netxmpp__:form:field:value' }},
                                          Values => { path => 'value/text()' },
					  Desc => { path => 'desc/text()' },
					  Required => { path => 'required' },
					  Option => { calls => [ qw /Get Add/ ],
						      type => 'child',
						      path => 'option',
						      child => { ns => '__netxmpp__:form:field:option' }}
                                         });

    $self->Client->AddNamespace(ns=>'__netxmpp__:form:field:value',
			        tag=>'value',
			        xpath => { 
                                           Value => { path => 'text()' }
                                         });

    $self->Client->AddNamespace(ns=>'__netxmpp__:form:field:option',
				tag=>'option',
				xpath => {
					  Value => { path => 'value/text()' },
					  Label => { path => '@label' }
					 });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/disco#items',
				tag=>'query',
				xpath => {
					  Item => {
						   calls => [ qw/Get Add/ ],
						   type => 'child',
						   path => 'item',
						   child => { ns => '__netxmpp__:disco:items' }
						  },
					  Node => { path => '@node' }
					 });

    $self->Client->AddNamespace(ns=>'__netxmpp__:disco:items',
				tag => 'item',
				xpath => {
					  JID => { path => '@jid', type=>'jid' },
					  Name => { path => '@name' },
					  Node => { path => '@node' }
					 });

    $self->Client->AddNamespace(ns=>'http://jabber.org/protocol/disco#info',
				tag=>'query',
				xpath => {
					  Identity => {
						       calls => [ qw/Get Add/ ],
						       type => 'child',
						       path => 'identity',
						       child => { ns => '__netxmpp__:disco:info:identity' }
						  },
					  Feature => {
						      calls => [ qw/Get Add/ ],
						      type => 'child',
						      path => 'feature',
						      child => { ns => '__netxmpp__:disco:info:feature' },
						     },
					  Node => { path => '@node' }
					 });

    $self->Client->AddNamespace(ns=>'__netxmpp__:disco:info:identity',
				tag => 'identity',
				xpath => {
					  Category => { path => '@category' },
					  Type => { path => '@type' },
					  Name => { path => '@name' }
					 });

    $self->Client->AddNamespace(ns=>'__netxmpp__:disco:info:feature',
				tag => 'feature',
				xpath => {
					  Var => { path => '@var' },
					 });

    $self->Client->AddNamespace(ns=>'vcard-temp',
	                        tag=>'vCard',
                                xpath => {
                                            Fn => { path => 'FN/text()' },
                                            GivenN => { path => 'N/GIVEN/text()' },
                                            FamilyN => { path => 'N/FAMILY/text()' },
                                            MiddleN => { path => 'N/Middle/text()' },
                                            NickName => { path => 'NICKNAME/text()' },
                                            Email => { path => 'EMAIL/INTERNET/USERID/text()' },
                                            JabberID => { path => 'JABBERID/text()' },
                                            VCard => { path => '.', type => 'raw' }
                                         });

    $self;
  }

use Getopt::Long;

sub cmd_pubsub
  {
    my ($self,$from,$type,$cmd,@args) = @_;

    return "Must be used as 'pubsub'" unless $cmd eq 'pubsub';

    my %opts = (affiliation=>'none',subscription=>'none',help=>0);
    my @opts = ("subid=s","affiliation=s","subscription=s");

    my $usage=<<EOH;
$cmd create      <node>
$cmd delete      <node>
$cmd purge       <node>
$cmd entities    <node>
$cmd setentity   <node> <jid> --subscription=<subscr> --affiliation=<aff>
$cmd subscribe   <node> --subid=<subid>
$cmd unsubscribe <node> --subid=<subid>
$cmd publishers  <node> {<jid>}+
EOH

    my $subcmd = shift @args;
    my $node = shift @args;
    local @ARGV = @args;
    return $usage unless $subcmd && $node;
    return $usage unless GetOptions(\%opts,@opts);

  SWITCH:
    {
      $subcmd eq 'create' and do
	{
	  return $self->Create(Node=>$node)->GetXML();
	},last SWTICH;

      $subcmd eq 'delete' and do
	{
	  return $self->Delete(Node=>$node)->GetXML();
	},last SWTICH;

      $subcmd eq 'purge' and do
	{
	  return $self->Purge(Node=>$node)->GetXML();
	},last SWTICH;

      $subcmd eq 'entities' and do
	{
	  return $self->GetEntities(Node=>$node)->GetXML();
	},last SWTICH;

      $subcmd eq 'setentity' and do {
	my $jid = shift @args;
	return $usage unless $jid;
	$self->SetEntities(Node=>$node,
			   Entities => {
					$jid => { Subscription => $opts{subscription},
						  Affiliation => $opts{affiliation} }
				       }
			   )->GetXML();
      },last SWITCH;

      $subcmd eq 'publishers' and do {

	my $msg = $self->GetEntities(Node=>$node);
	my %sub;
	if ($msg && $msg->GetChild("http://jabber.org/protocol/pubsub"))
	  {
	    my $pubsub = $msg->GetChild("http://jabber.org/protocol/pubsub");
	    foreach my $entity ($pubsub->GetEntities()->GetEntity())
	      {
		$sub{$entity->GetJID()} = $entity->GetSubscription();
	      }
	  }
	
	my %ents;
	foreach my $pub (@args)
	  {
	    $ents{$pub}->{Affiliation} = 'publisher';
	    $ents{$pub}->{Subscription} = $sub{$pub} || 'none';
	  }

	return $self->SetEntities(Node=>$node,Entities=>\%ents)->GetXML();
      },last SWITCH;

      $subcmd eq 'subscribe' and do
	{
	  return $self->Subscribe(Node=>$node,SubID=>$opts{subid})->GetXML();
	},last SWTICH;

      $subcmd eq 'unsubscribe' and do
	{
	  return $self->Unsubscribe(Node=>$node,SubID=>$opts{subid})->GetXML();
	},last SWTICH;
	
      $subcmd eq 'help' and do
	{
	  return "\n$usage";
	}
    };
  }

sub GetVCARD
  {
     my ($self,@opts) = @_;

     my $iq = $self->IQRequest(Type=>'get',Request=>sub { $_[0]->AddChild('vcard-temp'); },@opts); 
     $iq->GetChild('vcard-temp') if $iq;
  }

sub Subscribe
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $subscribe = $_[0]->AddSubscribe();
		       $subscribe->SetNode($_[1]->{Node});
		       $subscribe->SetJID($_[1]->{JID} || $_[2]->JID->GetJID('base'));
		       $subscribe->SetSubID($_[1]->{SubID}) if $_[1]->{SubID};
		     },
		     @opts);
  }

sub Unsubscribe
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $subscribe = $_[0]->AddUnsubscribe();
		       $subscribe->SetNode($_[1]->{Node});
		       $subscribe->SetJID($_[1]->{JID} || $_[2]->JID->GetJID('base'));
		       $subscribe->SetSubID($_[1]->{SubID}) if $_[1]->{SubID};
		     },
		     @opts);
  }

sub Publish
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $publish = $_[0]->AddPublish();
		       $publish->SetNode($_[1]->{Node} || $_[2]->cfg('PubSub','Node'));
		       my $item = $publish->AddItem();
		       $item->SetId($_[1]->{Id} || $_[2]->gen_uuid);
		       $item->SetContent($_[1]->{Content});
		     },
		     @opts);
  }

sub Create
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $create = $_[0]->AddCreate();
		       $create->SetNode($_[1]->{Node})
		     },
		     @opts);
  }

sub Delete
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $delete = $_[0]->AddDelete();
		       $delete->SetNode($_[1]->{Node})
		     },
		     @opts);
  }

sub Purge
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $purge = $_[0]->AddPurge();
		       $purge->SetNode($_[1]->{Node})
		     },
		     @opts);
  }

sub Retract
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request => sub{
		       my $retract = $_[0]->AddRetract();
		       $retract->SetNode($_[1]->{Node});
		       my $item = $retract->AddItem();
		       $item->SetId($_[1]->{Id});
		     },@opts);
  }

sub GetEntities
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Request=>sub {
		       my $entities = $_[0]->AddEntities();
		       $entities->SetNode($_[1]->{Node})
		     },
		     @opts);
  }

sub SetEntities
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Type=>'set',
		     Request=>sub {
		       my $entities = $_[0]->AddEntities();
		       $entities->SetNode($_[1]->{Node});
		       die "Entities option must be a HASH" unless ref $_[1]->{Entities} eq 'HASH';
		       foreach my $jid (keys %{$_[1]->{Entities}}) {
			 my $entity = $entities->AddEntity();
			 $entity->SetJID($jid);
			 $entity->SetAffiliation($_[1]->{Entities}->{$jid}->{Affiliation});
			 $entity->SetSubscription($_[1]->{Entities}->{$jid}->{Subscription});
		       }
		     },
		     @opts);
  }

sub DiscoverNodes
  {
    my ($self,@opts) = @_;

    $self->IQRequest(NS=>'http://jabber.org/protocol/disco#items',
		     Request=>sub { $_[0]->SetNode($_[1]->{Node}) if $_[1]->{Node} },
		     @opts);
  }


sub DiscoverNode
  {
    my ($self,@opts) = @_;

    $self->IQRequest(NS=>'http://jabber.org/protocol/disco#info',
		     Request=>sub { $_[0]->SetNode($_[1]->{Node}) if $_[1]->{Node} },
		     @opts);
  }

sub GetAffiliations
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Request=>sub { $_[0]->AddAffiliations(); },@opts);
  }

sub ConfigureNode
  {
    my ($self,@opts) = @_;

    $self->IQRequest(NS=>'http://jabber.org/protocol/pubsub#owner',
		     Request=> sub {
		       my $c = $_[0]->AddConfigure();
		       $c->SetNode($_[1]->{Node});
		     },@opts);
  }

sub GetItems
  {
    my ($self,@opts) = @_;

    $self->IQRequest(Request => sub {
		       my $elt = $_[0]->AddItems();
		       $elt->SetNode($_[1]->{Node});
		     },@opts);
  }

sub ParentNode
  {
    my ($self,$n) = @_;

    my @p = split '/',$n;
    my $len = scalar @p;
    join('/',@p[0..$len-2]);
  }

sub NodePath
  {
    my ($self,$n) = @_;

    my @path;
    my @p = split '/',$n;
    for (my $i = 0; $i < @p; $i++)
      {
	push(@path,join('/',@p[0..$i]));
      }
    @path;
  }

sub GetFormFieldValue
  {
    my ($self,$msg,$var,$ns) = @_;

    my $q = $msg->GetIQ($ns || 'http://jevent.it.su.se/NS/command');

    return undef unless $q;

    my $form = $q->GetChild('jabber:x:data');
    return undef unless $form;

    return undef unless $form->GetType() eq 'submit';

    foreach my $field ($form->GetField())
      {
	next unless $field->GetVar() eq $var;
	return $field->GetValues();
      }

    undef;
  }

sub AddCGIForm
  {
    my ($self,$q,$cgi,@fields) = @_;

    my @result;
    foreach my $f (@fields)
      {
	push(@result,{Var => $f, Value => [$cgi->param($f) || 0]});
      }

    return $self->AddForm($q,@result);
  }

sub AddForm
  {
    my ($self,$q,@fields) = @_;

    my $form = $q->NewChild('jabber:x:data');
    $form->SetType('submit');
    foreach (@fields)
      {
        my @v = ref $_->{Value} eq 'ARRAY' ? @{$_->{Value}} : ($_->{Value});
        next unless @v;
	my $field = $form->AddField();
	$field->SetVar($_->{Var});
	foreach my $v (@v)
	  {
	    $field->AddValue()->SetValue($v);
	  }
      }

    $q;
  }

sub SubmitForm
  {
    my ($self,@opts) = @_;
    my %opts = @opts;

    $self->IQRequest(Type=>'set',
		     NS=>$opts{NS} || 'http://jabber.org/protocol/commands',
		     Request=>sub { $_[2]->AddForm($_[0],@{$_[1]->{Fields}}) },
		     @opts);
  }

sub RequestIQForm
  {
    my ($self,@args) = @_;

    my %args = @args;
    my $iq = Net::XMPP::IQ->new();
    $iq->SetIQ(type=>'get',
               from=>$args{From},
               to=>$args{To});

    my $q = $iq->NewChild($args{NS} || 'http://jabber.org/protocol/commands');
    $self->AddFormRequest($q,@args);
    $self->Client->SendAndReceiveWithID($iq,$self->{Timeout});
  }

sub RequestMessageForm
  {
    my ($self,@args) = @_;

    my %args = @args;
    my $msg = Net::XMPP::Message->new();
    $msg->SetFrom($args{From});
    $msg->SetTo($args{To});
    $msg->SetBody($args{Body});

    my $q = $msg->NewChild($args{NS} || 'http://jabber.org/protocol/commands');
    $self->AddFormRequest($msg,@args);
    $self->Client->SendAndReceiveWithID($msg,$self->{Timeout});
  }

sub AddFormRequest
  {
    my ($self,$elt,%args) = @_;

    my $form = $elt->NewChild('jabber:x:data');
    $form->SetTitle($args{Title});
    $form->SetType($args{type} || 'form');
    $form->SetInstructions($args{Instructions});
    foreach (@{$args{Fields}})
      {
	my $field = $form->AddField();
	$field->SetVar($_->{Var});
	$field->SetType($_->{Type});
	$field->SetLabel($_->{Label});
	$field->SetDesc($_->{Desc});
	$field->SetRequired($_->{Required});
	my @v = ref $_->{Value} eq 'ARRAY' ? @{$_->{Value}} : ($_->{Value});
	if ($_->{Type} =~ /-multi/)
	  {
	    foreach my $v (@v)
	      {
		$field->AddValue()->SetValue($v);
	      }
	  }
        elsif ($_->{Type} =~ /boolean/)
          {
             $field->AddValue()->SetValue($v[0] ? '1' : '0');
          }
	else
	  {
	    $field->AddValue()->SetValue($v[0]);
	  }
      }
  }

sub IQRequest
  {
    my ($self,%opts) = @_;

    my $iq = Net::XMPP::IQ->new();
    $iq->SetIQ(type=>$opts{Type} || 'get',
	       from=>$opts{From} || $self->JID()->GetJID('base'),
	       to=>$opts{To} || $opts{Host} || $self->cfg('PubSub','Host') || $self->Hostname);

    my $elt = $iq->NewChild($opts{NS} || 'http://jabber.org/protocol/pubsub');
    &{$opts{Request}}($elt,\%opts,$self);

    $self->Client->SendAndReceiveWithID($iq,$self->{Timeout});
  }

sub FormFieldVars
  {
    my ($self,$form) = @_;

    [map { $_->GetVar() } $form->GetField()];
  }

sub SubmitCGIForm
  {
    my ($self,$q,$fields,@rest) = @_;


    my @fspec;
    foreach my $field (@{$fields})
      {
	push(@fspec,{Var=>$field,Value=>[$q->param($field)]});
      }

    $self->SubmitForm(Fields=>\@fspec,@rest);
  }

sub FormHTML
  {
    my ($self,$form,$q,%opts) = @_;

    my $out = "<table class=\"xmpp-form\">\n";
    foreach my $field ($form->GetField())
      {
	my $type = $field->GetType();
	my $label = $field->GetLabel() || $field->GetVar();
	
	unless ($type eq 'hidden')
	  {
	    $out .= "<tr class=\"xmpp-form-field\">\n";
	    $out .= "<td class=\"xmpp-form-label\">$label</td>";
	    $out .= "<td class=\"xmpp-form-widget\">";
	  }
	my $var = $field->GetVar();
	my @value = $field->GetValues();

      TYPE:
	{
	  $type eq 'fixed' and do
	    {
	      $out .= join("<br/>",@value);
	    },last TYPE;

	  $type eq 'hidden' and do
	    {
	      $out .= $q->hidden(-name=>$var,-value=>\@value);
	    },last TYPE;

	  $type eq 'text-private' and do
	    {
	      $out .= $q->password_field(-name=>$var,-value=>$value[0],size=>20);
	    },last TYPE;

	  $type eq 'boolean' and do
	    {
	      $out .= $q->checkbox(-name=>$var,-label=>'',-checked=>$value[0],-value=>1);
	    },last TYPE;

	  $type eq 'text-single' || $type eq 'jid-single' and do
	    {
	      $out .= $q->textfield(-name=>$var,-default=>$value[0],-size=>20);
	    },last TYPE;

	  $type eq 'text-multiple' || $type eq 'jid-multiple' and do
	    {
	      $out .= $q->textarea(-name=>$var,-default=>join("\n",@value),-rows=>6,-cols=>40);
	    },last TYPE;

	  $type eq 'list-single' || $type eq 'list-multiple' and do
	    {
	      my %lab;
	      my @opt;
	      foreach my $o ($field->GetOption())
		{
		  my $ov = $o->GetValue();
		  push(@opt,$ov);
		  $lab{$ov} = $o->GetLabel() || $ov;
		}
	      $out .= $q->popup_menu(-name=>$var,
				     -values=>\@opt,
				     -labels=>\%lab,
				     -default=>$field->GetValue());
	    },last TYPE;
	};

	unless ($type eq 'hidden')
	  {
	    $out .= "</td>\n";
	    $out .= "</tr>\n";
	  }
      }

    $out .= "</table>\n";

    $out;
  }

sub Usage
  {
    my $uid = $_[0]->Username;
    my $desc = $_[0]->{Description} || "Hello I am $uid";
    $desc .= "\nYou can also call me ".join(',',$_[0]->handles) if $_[0]->handles;

    $desc;
  }

sub handles
  {
     keys %{$_[0]->{_handles}};
  }

sub addHandle
  {
     $_[0]->{_handles}->{$_[1]}++; 
  }

sub delHandle
  {
     delete $_[0]->{_handles}->{$_[1]};
  }

sub isValidHandle
  {
     my ($self,$handle) = @_;
     return 1 if $handle eq $self->Username;
     return 1 if $handle eq $self->JID->GetJID("base");

     return grep { $_ eq $handle } $self->handles();
  }

sub evalCommand
  {
    my ($self,$sid,$msg) = @_;

    my $type = $msg->GetType();
    my $body = $msg->GetBody();
    my $from = Net::XMPP::JID->new($msg->GetFrom());
    my $sendto = $from;

    my $delay = $msg->GetChild('jabber:x:delay');
    return undef if $delay;

    my $event = $msg->GetChild('http://jabber.org/protocol/pubsub#event');
    return undef if $event;

    if ($type eq 'groupchat')
      {
	return undef unless $body =~ s/^\s*(\S+):\s*//o;
	return undef unless $self->isValidHandle($1);
        $sendto = $from->GetJID('base');
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
		    return undef;
		  }

		$self->{_rooms}->{$room_jid}++;
                &{$self->{MUCEventCB}}($self,$room_jid,'join') if ref $self->{MUCEventCB} eq 'CODE';
		return $self->Client->MessageSend(from=>$self->JID->GetJID("base"),
						  to=>$room_jid->GetJID("base"),
						  type=>'groupchat',
						  body=>$self->Usage());
	      }
	  }
      }

    my $r = &{$self->{MessageHook}}($self,$sid,$msg) if $self->{MessageHook} eq 'CODE';
    return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>$r) if $r;

    return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>"I have no commands configured.\n")
      unless ref $self->{Commands} eq 'HASH';

    my ($cmd,$args);

    return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>"I don't understand this: \"$body\"")
      unless ($cmd,$args) = $body =~ /^\s*(\S+)\s*(.*)\s*$/o;

    my @args = split /\s+/,$args;

  BUILTIN:
    {
      $cmd eq '?' || $cmd eq 'help' || $cmd eq 'who' and do {

	my $cbody = $self->Usage."\nCommands: \n\n";
	foreach my $c (keys %{$self->{Commands}})
	  {
	    $cbody .= sprintf "%s\n",(defined $self->{CommandInfo}->{$c} ? $self->{CommandInfo}->{$c}->[0] : $c);
	  }
	return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>$cbody);
      },last BUILTIN;
    }


    if (ref $self->{Commands}->{$cmd} eq 'CODE')
      {
	if (ref $self->{CommandAuthorization} eq 'CODE')
	  {
	    return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>'Not authorized')
	      unless &{$self->{CommandAuthorization}}($self,$from->GetJID("base"),$type,$cmd,@args);
		
	  }
	
	my $cresult = &{$self->{Commands}->{$cmd}}($self,$from->GetJID("base"),$type,$cmd,@args);
	return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>$cresult) if $cresult;
      }
    else
      {
	return $self->Client->MessageSend(to=>$sendto,type=>$type,body=>"No such command: \"$cmd\"")
      }
  }

sub spocpCommandAuthorization
  {
    my ($self,$from,$cmd,@args) = @_;

    return 1 unless $self->{SPOCPServer};

    my $spocp = Net::SPOCP::Client->new(server=>$self->{SPOCPServer});
    my $to = $self->JID->GetJID("base");
    my $res = $spocp->query([jevent => [command => $cmd],[from => $from],[to => $to]]);
    return !$res->is_error;
  }

sub spocpSubscriptionAuthorization
  {
    my ($self,$sid,$msg) = @_;

    return 1 unless $self->{SPOCPServer};

    my $spocp = Net::SPOCP::Client->new(server=>$self->{SPOCPServer});
    my $to = $self->JID->GetJID("base");
    my $from = Net::XMPP::JID->new($msg->GetFrom())->GetJID("base");
    my $res = $spocp->query([jevent => [method => 'subcribe'],[from => $from],[to => $to]]);
    return !$res->is_error;
  }

sub PreExecute() { }

sub PostExecute() { }

sub Connect
  {
    my $self = shift;
    my %opts = @_;

    my $status =
      $self->Client->Connect(hostname=>$self->Hostname,
			     tls=>$self->{UseTLS},
			     tlsoptions=>{
					  SSL_verify_mode=>$self->{SSLVerify}||0x01 , #require
					  SSL_ca_file=>$self->{CAFile}||'/etc/ssl/ca.crt',
					  SSL_ca_dir=>$self->{CADir}
					 },
			     resource=>$self->Resource,
			     processtimeout=>$self->{ProcessTimeout} || 1,
			     register=>0);
    die "Unable to connect" unless $status;
    $self->Client->AuthSend(username=>$self->Username,
			    password=>$self->Password,
			    resource=>$self->Resource);
    $self;
  }

sub Disconnect
  {
    $_[0]->Client->Disconnect();
  }

sub Run
  {
    my $self = shift;
    my $code = shift if ref $_[0] eq 'CODE';
    my %opts = @_;

    $self->{MessageCB} = \&evalCommand unless ref $self->{MessageCB} eq 'CODE';
    $self->{CommandAuthorization} = \&spocpCommandAuthorization
      unless ref $self->{CommandAuthorization} eq 'CODE';
    $self->{SubscriptionAuthorization} = \&spocpSubscriptionAuthorization
      unless ref $self->{SubscriptionAuthorization} eq 'CODE';
    $self->{Data} = $opts{Data} if $opts{Data};

    unless ($code)
      {
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
	$self->PostExecute();
      }
    else
      {
	my $status =
	  $self->Client->Connect(hostname=>$self->Hostname,
				 tls=>$self->{UseTLS},
				 tlsoptions=>{
					      SSL_verify_mode=>$self->{SSLVerify}||0x01 , #require
					      SSL_ca_file=>$self->{CAFile}||'/etc/ssl/ca.crt',
					      SSL_ca_dir=>$self->{CADir}
					     },
				 resource=>$self->Resource,
				 processtimeout=>$self->{ProcessTimeout} || 1,
				 register=>0);
	die "Unable to connect" unless $status;
	$self->Client->AuthSend(username=>$self->Username,
				password=>$self->Password,
				resource=>$self->Resource);

	my $result = &{$code}($self);

	$self->Client->Disconnect();

	return $result;
      }
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
                      to the server.

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

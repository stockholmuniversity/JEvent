#!/pkg/perl/default/bin/perl

use SUCGI2;
use JEvent;
use XML::Parser;


# xml pp algorithm by Matt Sergeant <matt.sergeant at bbc.co.uk>
sub _xmlpp
  {
    my ($q,$xml) = @_;

    eval
      {

	$q->print(XML::Parser->new(Handlers => {
						# Handlers using closures, except Start 'cos it's more complex.
						# $_[0] is the expat object where we store the HTML output
						Init => sub { $_[0]->{html} = '<pre>' },
						Final => sub { $_[0]->{html} .= "</pre>"; return $_[0]->{html} },
						Start => \&_xml_elt_start,
						End => \&_xml_elt_end,
						Char => sub {
						  $_[0]->{html} .= "<b>$_[1]</b>";
						  $_[0]->{newline} = 0;
						},
						CdataStart => sub {
						  $_[0]->{html} .= '<font color="yellow">';
						  $_[0]->{newline} = 0;
						},
						CdataEnd => sub {
						  $_[0]->{html} .= '</font>';
						  $_[0]->{newline} = 0;
						},
					       }
				  )->parse($xml));
      };
    if ($@)
      {
	my $err = $@;
	$err =~ s/at\s+(.+)\s+line\s+([0-9]+)$//og;
	$q->print("<strong>XML Parsing error: </strong><em>$err</em>");
      }
  }

sub _indent
  {
    my $expat = shift;
    my $extra = shift;

    my $out = "";
    for ($i = 0; $i < $expat->{depth}; $i++)
      {
	$out .= "&nbsp;&nbsp;&nbsp;";
      }
    for ($i = 0; $i < $extra; $i++)
      {
        $out .= "&nbsp;";
      }
    $out;
  }

sub _xml_elt_end
  {
    my $expat = shift;
    my $element = shift;

    $expat->{newline} = 0 if $expat->{last} eq $element;
    $expat->{depth}--;
    $expat->{html} .= "<br/>" if $expat->{newline};
    $expat->{html} .= ($expat->{newline} ? _indent($expat) : '').'&lt;/<font color="green">' . $element .'</font>&gt;';
    delete $expat->{last};
    $expat->{newline} = 1 unless $expat->{newline};
  }

sub _xml_elt_start
  {
    my $expat = shift;
    my $element = shift;
    my %attribs = @_;

    $expat->{html} .= "<br/>" if $expat->{newline};
    $expat->{html} .= _indent($expat);
    $expat->{html} .= '&lt;<font color="green">' . $element . '</font>';
    if (%attribs)
      {
        my $ca = 0;
	foreach (keys %attribs) {
	  $expat->{html} .= ($ca++ == 0 ? "" : "\n"._indent($expat,length($element)+1)).' <font color="red">'.$_.'</font>=&quot;<font color="blue">'.$attribs{$_}.'</font>&quot;';
	}
      }
    $expat->{html} .= '&gt;';
    $expat->{depth}++;
    $expat->{newline} = 1;
    $expat->{last} = $element;
  }


my $cgiini =  Config::IniFiles->new(-file=>'/var/httpd/conf/sucgi.ini');
my $ini =  Config::IniFiles->new(-file=>'/var/httpd/conf/pubsub.ini');

my $q = SUCGI2->new($cgiini,'pubsub');
eval { $q->authenticate() };

if ($@) {
    my $e = $@;
    $q->begin (title=>'XMPP PubSub Administration');
    $q->print ("&nbsp;<p><ul><font COLOR='red' SIZE='3'><strong>SUCGI2 authentication failed: $e</strong></font></ul>\n\n");
    $q->end ();
    die ("SUCGI2 authentication failed: $e");
}

my $cmd = $q->param('_cmd');
$cmd = 'browse' unless $cmd;
my $me = $q->state_url();

my $qhost = $q->param('_host');
$qhost = 'pubsub.cdr.su.se' unless $qhost;
my $qnode = $q->param('_node');
my $message = $q->param('_message');

my $sidebar = <<EOH;
<br/>
&nbsp;&raquo;&nbsp;<a href="$me&_cmd=browse&_host=$qhost"><strong>$qhost</strong></a><br/>
<br/>
EOH

$sidebar .= <<EOH;
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_cmd=browse&_host=$qhost&_node=$qnode">Manage Nodes</a><br/>
<br/>
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_host=$qhost&_node=$qnode&_cmd=configure\">Configure Node</a><br/>
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_host=$qhost&_node=$qnode&_cmd=affiliations\">Show Affiliations</a><br/>
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_host=$qhost&_node=$qnode&_cmd=entities\">Edit Affiliations</a><br/>
<br/>
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_host=$qhost&_node=$qnode&_cmd=showitems\">Show Items</a><br/>
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_host=$qhost&_node=$qnode&_cmd=purge\">Purge Items</a><br/>
&nbsp;&nbsp;&nbsp;&raquo;&nbsp;<a href="$me&_host=$qhost&_node=$qnode&_cmd=publish\">Publish Item</a><br/>
EOH

$q->begin(title=>'XMPP PubSub Administration',sidebar=>$sidebar);
eval
  {	

    my $je = JEvent->new(Config => $ini)
      or die "Unable to create JEvent interface";

    $je->Connect();

    $q->print($q->start_form());
    $q->print($q->hidden(-name=>'_host',-value=>$qhost));
    $q->print($q->hidden(-name=>'_node',-value=>$qnode));
    $q->print($q->hidden(-name=>'_cmd',-value=>$cmd));

    $q->print("<h1>");
    $q->print("<a href=\"$me&_cmd=$cmd&_host=$qhost&_node=\"><b>/</b></a>");
    if ($qnode)
      {
	my @links;
	foreach my $part ($je->NodePath($qnode))
	  {
	    my @parts = split '/',$part;
	    my $partname = pop @parts;
	    push(@links,"<a href=\"$me&_cmd=$cmd&_host=$qhost&_node=$part\">$partname</a>");
	  }
	$q->print(join('/',@links));
      }
    $q->print("</h1>");
    $q->print($message) if $message;

  CASE:
    {
      $cmd eq 'doconfigure' and do
	{
	  my $iq = Net::XMPP::IQ->new();
	  $iq->SetIQ(type=>'set',to=>$qhost);
	  my $pubsub = $iq->NewChild('http://jabber.org/protocol/pubsub#owner');
          my $configure = $pubsub->AddConfigure();
	  $configure->SetNode($qnode);
	  $je->AddCGIForm($configure,$q,$q->param('_fields'));
          warn $iq->GetXML();
	  my $msg = $je->Client->SendAndReceiveWithID($iq,$self->{Timeout});
	  die $msg if $msg->GetType() eq 'error';
	  $cmd = 'configure';
	  $message = "<p>Node <strong>$qhost</strong>/$qnode configuration updated</p>";
	};

      $cmd eq 'doaddentity' || $cmd eq 'dodelentity' and do
	{
	  my $msg = $je->GetEntities(Host=>$qhost,Node=>$qnode);
	  last CASE unless $msg;
	  die $msg if $msg->GetType() eq 'error';
	  my $pubsub = $msg->GetChild('http://jabber.org/protocol/pubsub');
	  $pubsub = $msg->GetChild('http://jabber.org/protocol/pubsub#event') unless $pubsub;
	  die "No &lt;pubsub/&gt; element\n" unless $pubsub;
	  my $entities = $pubsub->GetEntities();
	  die "No &lt;entites/&gt; element\n" unless $entities;

	  my %entities;
	  foreach my $ent ($entities->GetEntity())
	    {
	      $entities{$ent->GetJID()} = {Affiliation => $ent->GetAffiliation(),
					   Subscription => $ent->GetSubscription()};
	    }

	  if ($cmd eq 'doaddentity')
	    {
	      foreach my $jid ($q->param('_jids'))
		{
		  if (defined $q->param('_a:'.$jid))
		    {
		      $entities{$jid}->{Affiliation} = $q->param('_a:'.$jid);
		    }
		  else
		    {
		      delete $entities{$jid}->{Affiliation};
		    }

		  if (defined $q->param('_s:'.$jid))
		    {
		      $entities{$jid}->{Subscription} = $q->param('_s:'.$jid);
		    }
		  else
		    {
		      delete $entities{$jid}->{Subscription};
		    }
		}

	      $entities{$q->param('_a_jid')}->{Affiliation} = $q->param('_a_a');
	      $entities{$q->param('_a_jid')}->{Subscription} = $q->param('_a_s');
	    }

	  if ($cmd eq 'dodelentity')
	    {
	      foreach my $jid ($q->param('_delete'))
		{
		  delete $entities{$jid};
		}
	    }

	  $je->SetEntities(Host=>$qhost,Node=>$qnode,Entities=>\%entities);

	  $cmd = 'entities';
	};

      $cmd eq 'docreate' and do
	{
	  foreach my $node (map { $qnode.'/'.$_ } $je->NodePath($q->param('_path')))
	    {
	      my $msg = $je->Create(Host=>$qhost,Node=>$node);
	      die $msg if $msg->GetType() eq 'error';
	      $message .= "<p>Node <strong>$qhost</strong>/$node created</p>";
	    }
	  $cmd = 'browse';
	};

      $cmd eq 'dodelete' and do
	{
	  foreach my $node ($q->param('_delete'))
	    {
	      my $msg = $je->Delete(Host=>$qhost,Node=>$node);
	      die $msg if $msg->GetType() eq 'error';
	      $qnode = $je->ParentNode($node);
	      $message .= "<p>Node <strong>$qhost</strong>/$node deleted</p>";
	    }
	  $cmd = 'browse';
	};

      $cmd eq 'dodelitems' and do
	{
	  my @ids;
	  foreach my $id ($q->param('_delete'))
	    {
	      my $msg = $je->Retract(Host=>$qhost,Node=>$qnode,Id=>$id);
	      die $msg if $msg->GetType() eq 'error';
	      $message .= "<p>Item <strong>$qhost</strong>/$node!$id deleted</p>";
	    }
	  $cmd = 'showitems';
	};

      $cmd eq 'dopurge' and do
	{
	  my $msg = $je->Purge(Host=>$qhost,Node=>$qnode);
	  die $msg if $msg->GetType() eq 'error';
	  $cmd = 'showitems';
	  $message = "<p>Node <strong>$qhost</strong>/$qnode purged</p>";
	};

      $cmd eq 'dopublish' and do
	{
	  my $content = $q->param('_content');
	  my $msg = $je->Publish(Host=>$qhost,Node=>$qnode,Content=>$content,Id=>$q->param('_id'));
	  die $msg if $msg->GetType() eq 'error';
	  $cmd = 'showitems';
	};

      $cmd eq 'publish' and do
	{
	  $q->print("<strong>ID</strong> (leave empty to generate)<br/>\n");
	  $q->print($q->textfield(-name=>_id,-value=>'',-size=>20));
	  $q->print("<br/><br/>");
	  $q->print("<strong>Content (XML)</strong><br/>\n");
	  $q->print($q->textarea(-name=>_content,-value=>'',-rows=>8,-cols=>40));
	  $q->print("<br/><br/>");
	  $q->print($q->button(-name=>'_button.publish',-value=>'Publish',
			       -onClick=>'this.form._cmd.value=\'dopublish\'; this.form.submit()'));
	  $q->print("&nbsp;");
	  $q->print($q->button(-name=>'_button.cancel',-value=>'Cancel',
			       -onClick=>'this.form._cmd.value=\'browse\'; this.form.submit()'));
	},last CASE;

      $cmd eq 'showitems' and do
	{
	  my $msg = $je->GetItems(Node=>$qnode,Host=>$qhost);
	  die "Request timed out\n" unless $msg;
	  my $items = $msg->GetQuery('http://jabber.org/protocol/pubsub');
	  $items = $msg->GetQuery('http://jabber.org/protocol/pubsub#event') unless $items;
	  die "No &lt;items/&gt; element in response\n" unless $items;
	  my $i2 = $items->GetItems();
	  if ($i2 && $i2->GetItems()) # Yes it is confusing ;-)
	    {
	      $q->print("<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\">\n");
	      my $i = 0;
	      foreach my $item ($i2->GetItems())
	      {
		my $cl = $i++ % 2 ? 'sucgi-table-row-even' : 'sucgi-table-row-odd';

		$q->print("<tr>");
		$q->print("<td class=\"$cl\">");
		my $id = $item->GetId();
		$q->print($q->checkbox(-name=>'_delete',-label=>$id,-checked=>0,-value=>$id));
		$q->print("</td>\n");
		$q->print("</tr>");
		$q->print("<tr><td style=\"font-size: xx-small;\" class=\"$cl\">");
		_xmlpp($q,$item->GetContent());
		$q->print("</td></tr>");
	      }
	      $q->print("</table><br/>\n");
	      $q->print($q->button(-name=>'_button.delete',-value=>'Delete Items',
				   -onClick=>'this.form._cmd.value=\'dodelitems\'; this.form.submit()'));
	      $q->print("&nbsp;");
	      $q->print($q->button(-name=>'_button.publish',-value=>'Publish New Item',
				   -onClick=>'this.form._cmd.value=\'publish\'; this.form.submit()'));
	    }
	  else
	    {
	      $q->print("<p>No items in \"$qnode\"</p>\n");
	    }
	},last CASE;

      $cmd eq 'browse' and do
	{
	  # items

	  my $msg = $je->DiscoverNodes(Node=>$qnode,Host=>$qhost);
	  die "Request timed out\n" unless $msg;
	  my $query = $msg->GetQuery('http://jabber.org/protocol/disco#items');
	  die "No &lt;query/&gt; element in #items response\n" unless $query;

	  if($query->GetItem())
	    {
	      $q->print("<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\">\n");
	      $q->print("<tr><th>Delete</th><th>Node</th></tr>\n");
	      my $i = 0;
	      my %ic;
	      foreach my $item ($query->GetItem())
		{
		  my $cl = $i++ % 2 ? 'sucgi-table-row-even' : 'sucgi-table-row-odd';

		  my $jid = $item->GetJID();
		  my $node = $item->GetNode();
		  $node =~ s/!([^!]+)$//og;
		  next if $node eq $qnode;
		  next if $ic{$node}++;
		  $q->print("<tr>\n");
		  $q->print("<td class=\"$cl\">".$q->checkbox(-name=>'_delete',-checked=>0,-label=>'',-value=>$node)."</td>");
		  $q->print("<td class=\"$cl\"><a href=\"$me&_host=$jid&_node=$node\">$node</a></td>");
		  $q->print("</tr>\n");
		}
	      $q->print("</table>\n");
	    }
	  else
	    {
	      $q->print("<p>No subordinate nodes</p>\n");
	    }
	  $q->print("<br/>");
	  $q->print($q->button(-name=>'_button.delete',-value=>'Delete Nodes',
			       -onClick=>'this.form._cmd.value=\'dodelete\'; this.form.submit();'));
	  $q->print("&nbsp;");
	  $q->print($q->textfield(-name=>'_path',-size=>20,-value=>''));
	  $q->print("&nbsp;");
	  $q->print($q->button(-name=>'_button.create',-value=>'Create Node',
			       -onClick=>'this.form._cmd.value=\'docreate\'; this.form.submit();'));
	},last CASE;

      $cmd eq 'configure' and do
	{
	  my $msg = $je->ConfigureNode(Node=>$qnode,Host=>$qhost);
	  last CASE unless $msg;
	  die $msg if $msg->GetType() eq 'error';
	  my $iq = $msg->GetChild('http://jabber.org/protocol/pubsub#owner');
	  last CASE unless $iq;
	  my $configure = $iq->GetConfigure();
	  last CASE unless $configure;
	  my $form = $configure->GetForm();
	  if ($form)
	    {
	      $q->print("<p>".$form->GetInstructions()."</p>\n") if $form->GetInstructions();
	      $q->print($je->FormHTML($form,$q));
	      $q->print($q->hidden(-name=>'_fields',-value=>$je->FormFieldVars($form)));
              my $submit = $q->button(-name=>'_button.configure',
                                      -value=>'Configure Node',
                                      -onClick=>'this.form._cmd.value=\'doconfigure\'; this.form.submit()');
	      $q->print("</br>".$submit."&nbsp;".$q->reset());
	    }
	},last CASE;

      $cmd eq 'affiliations' and do
	{
	  my $msg = $je->GetAffiliations(Node=>$qnode,Host=>$qhost);
	  last CASE unless $msg;
	  die $msg if $msg->GetType() eq 'error';
	  my $pubsub = $msg->GetChild('http://jabber.org/protocol/pubsub');
	  $pubsub = $msg->GetChild('http://jabber.org/protocol/pubsub#event') unless $pubsub;

	  die "No &lt;pubsub/&gt; element\n" unless $pubsub;
	  my $affiliations = $pubsub->GetAffiliations();
	  die "No &lt;affiliations/&gt; element\n" unless $affiliations;

	  $q->print("<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\">\n");
	  $q->print("<tr><th>Node</th><th>JID</th><th>Affiliation</th><th>Subscription</th><th>SubID</th></tr>\n");

	  my $i = 0;
	  foreach my $aff ($affiliations->GetEntity())
	    {
	      my $cl = $i++ % 2 ? 'sucgi-table-row-even' : 'sucgi-table-row-odd';

	      $q->print("<tr>\n");
	      $q->print("<td class=\"$cl\">");
	      $q->print($aff->GetNode());
	      $q->print("</td>");
	      $q->print("<td class=\"$cl\">");
	      $q->print($aff->GetJID());
	      $q->print("</td>");
	      $q->print("<td class=\"$cl\">");
	      $q->print($aff->GetAffiliation());
	      $q->print("</td>");
	      $q->print("<td class=\"$cl\">");
	      $q->print($aff->GetSubscription());
	      $q->print("</td>");
	      $q->print("<td class=\"$cl\">");
	      $q->print($aff->GetSubID());
	      $q->print("</td>");
	      $q->print("</tr>\n");
	    }
	  $q->print("</table>\n");
	},last CASE;

      $cmd eq 'entities' and do
	{
	  my $msg = $je->GetEntities(Node=>$qnode,Host=>$qhost);
	  last CASE unless $msg;
	  die $msg if $msg->GetType() eq 'error';
	  my $pubsub = $msg->GetChild('http://jabber.org/protocol/pubsub');
	  $pubsub = $msg->GetChild('http://jabber.org/protocol/pubsub#event') unless $pubsub;
	  die "No &lt;pubsub/&gt; element\n" unless $pubsub;
	  my $entities = $pubsub->GetEntities();
	  die "No &lt;entites/&gt; element\n" unless $entities;
	  $q->print("<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\">\n");
	  $q->print("<tr><th>Delete</th><th>Node</th><th>JID</th>");
	  $q->print("<th>Affiliation</th><th>Subscription</th><th>SubID</th></tr>\n");

	  my @jids;
	  my $i = 0;
	  foreach my $ent ($entities->GetEntity())
	    {
	      my $cl = $i++ % 2 ? 'sucgi-table-row-even' : 'sucgi-table-row-odd';
	      my $jid = $ent->GetJID();
	      push(@jids,$jid);
	      $q->print("<tr>\n");

	      $q->print("<td class=\"$cl\">\n");
	      $q->print($q->checkbox(-name=>'_delete',-value=>$jid,-checked=>0,-label=>''));
	      $q->print("</td>\n");

	      $q->print("<td class=\"$cl\">\n");
	      $q->print($ent->GetNode() || $entities->GetNode() || '(empty)');
	      $q->print("</td>\n");

	      $q->print("<td class=\"$cl\">\n");
	      $q->print($jid);
	      $q->print("</td>\n");

	      $q->print("<td class=\"$cl\">\n");
	      $q->print($q->popup_menu(-name=>'_a:'.$jid,
				       -values=>[qw/owner publisher none outcast/],
				       -default=>$ent->GetAffiliation()));
	      $q->print("</td>\n");

	      $q->print("<td class=\"$cl\">\n");
	      $q->print($q->popup_menu(-name=>'_s:'.$jid,
				       -values=>[qw/none pending unconfigured subscribed/],
				       -default=>$ent->GetSubscription()));
	      $q->print("</td>\n");

	      $q->print("<td class=\"$cl\">\n");
	      $q->print($ent->GetSubID());
	      $q->print("</td>\n");

	      $q->print("</tr>\n");
	    }
	  $q->print($q->hidden(-name=>'_jids',-value=>\@jids));
	  $q->print("<tr>\n");
	  $q->print("<td>&nbsp;</td>");
	  $q->print("<td>$qnode</td>");
	  $q->print("<td>".$q->textfield(-name=>'_a_jid',-size=>20)."</td>");
	  $q->print("<td>\n");
	  $q->print($q->popup_menu(-name=>'_a_a',-values=>[qw/owner publisher none outcast/],-default=>'none'));
	  $q->print("</td>\n");
	  $q->print("<td>\n");
	  $q->print($q->popup_menu(-name=>'_a_s',-values=>[qw/none pending unconfigured subscribed/],-default=>'none'));
	  $q->print("</td>\n");
	  $q->print("<td>&nbsp;</td>");
	  $q->print("</tr>\n");

	  $q->print("</table>\n");
	  $q->print($q->button(-name=>'_button.add',-value=>'Add',
			       -onclick=>'this.form._cmd.value=\'doaddentity\'; this.form.submit();'));
	  $q->print("&nbsp;");
	  $q->print($q->button(-name=>'_button.add',-value=>'Delete',
			       -onclick=>'this.form._cmd.value=\'dodelentity\'; this.form.submit();'));
	},last CASE;

      $cmd eq 'purge' and do
	{
	  $q->print("<p>Really purge all entires from ".($qnode ? $qnode : '(empty)')."?</p>\n");
	  $q->print($q->button(-name=>'_button.purge',-value=>'Purge Items',
			       -onClick=>'this.form._cmd.value=\'dopurge\'; this.form.submit();'));
	  $q->print("&nbsp;");
	  $q->print($q->button(-name=>'_button.purge',-value=>'Cancel',
			       -onClick=>'this.form._cmd.value=\'browse\'; this.form.submit();'));
	},last CASE;

      do {
	$q->print("<p>Unknown command</p>\n");
      },last CASE

    };

$q->print($q->end_form());

  };
if ($@)
  {
    my $msg = $@;
    my $info = ref $msg ? $msg->GetErrorCode() : $msg;
    $q->print("<h1>Error</h1>\n<h2>$info</h2>\n");
    $q->print("<div style=\"font-size: xx-small;\">\n");
    _xmlpp($q,$msg->GetXML()) if ref $msg;
    $q->print("</div>\n");
  }

$q->end();

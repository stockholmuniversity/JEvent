#!/pkg/perl/default/bin/perl

use SUCGI2;
use JEvent;

my $cgiini =  Config::IniFiles->new(-file=>'/var/httpd/conf/sucgi.ini');
my $ini =  Config::IniFiles->new(-file=>'/var/httpd/conf/disco.ini');

my $q = SUCGI2->new($cgiini,'disco');
eval {
    $q->authenticate();
};

if ($@) {
    my $e = $@;
    $q->begin (title=>'XMPP Discovery');
    $q->print ("&nbsp;<p><ul><font COLOR='red' SIZE='3'><strong>SUCGI2 authentication failed: $e</strong></font></ul>\n\n");
    $q->end ();
    die ("SUCGI2 authentication failed: $e");
}

my $cmd = $q->param('_cmd');
$cmd = 'browse' unless $cmd;
my $me = $q->state_url();


$q->begin(title=>'XMPP Disovery',sidebar=><<EOH);
<br/>
&nbsp;&raquo;&nbsp;<a href="$me&_cmd=browse&_host=cdr.su.se">cdr.su.se</a><br/>
&nbsp;&raquo;&nbsp;<a href="$me&_cmd=browse&_host=pubsub.cdr.su.se">pubsub.cdr.su.se</a><br/>
&nbsp;&raquo;&nbsp;<a href="$me&_cmd=browse&_host=xmpp1.su.se">xmpp1.su.se</a><br/>
&nbsp;&raquo;&nbsp;<a href="$me&_cmd=browse&_host=jabber.su.se">jabber.su.se</a><br/>
EOH

eval
  {	

    my $je = JEvent->new(Config => $ini)
      or die "Unable to create JEvent interface";

    my $qhost = $q->param('_host');
    my $qnode = $q->param('_node');

  CASE:
    {
      $cmd eq 'browse' and do
	{
	  $je->Connect();

	  # info

	  my $msg = $je->DiscoverNode(Node=>$qnode,Host=>$qhost);
	  die "Request timed out\n" unless $msg;

	  my $query = $msg->GetQuery('http://jabber.org/protocol/disco#info');
	  die "No &lt;query/&gt; element in #info response\n" unless $query;
	  my $tab = 0;
	  my $h1 = 0;

	  if ($msg && $query)
	    {
	      $q->print("<h1>".$msg->GetFrom()." ".$query->GetNode()."</h1>\n"),$h1++;
	    }

	  if ($query->GetIdentity())
	    {
	      $q->print("<table>\n"),$tab++;
	      $q->print("<tr>\n");
	      $q->print("<th>Identity</th>");
	      $q->print("<td style='background-color: lightgrey'><dl compact='compact'>");
	      foreach my $id ($query->GetIdentity())
		{
		  $q->print("<dt><strong>".$id->GetName()."</strong></dt>");
		  $q->print("<dd><dl><dt><em>Category</em></dt><dd>".$id->GetCategory."</dd>");
		  $q->print("<dt><em>Type</em></dt><dd>".$id->GetType()."</dd></dl></dd>");
		}
	      $q->print("</dl></td>");
	      $q->print("</tr>\n");
	    }

	  if ($query->GetFeature())
	    {
	      $q->print("<table>\n"),$tab++ unless $tab;
	      $q->print("<tr>\n");
	      $q->print("<th>Features</th>");
	      $q->print("<td style='background-color: lightgrey'><ul>");
	      foreach my $f ($query->GetFeature())
		{
		  $q->print("<li>".$f->GetVar()."</li>");
		}
	      $q->print("</ul></td>");
	      $q->print("</tr>\n");
	    }

	  $q->print("</table>\n") if $tab;

	  # items

	  $msg = $je->DiscoverNodes(Node=>$qnode,Host=>$qhost);
	  die "Request timed out\n" unless $msg;
	  my $query = $msg->GetQuery('http://jabber.org/protocol/disco#items');
	  die "No &lt;query/&gt; element in #items response\n" unless $query;

	  if ($msg && $query && !$h1)
	    {
	      $q->print("<h1>".$msg->GetFrom()." ".$query->GetNode()."</h1>\n"),$h1++;
	    }

	  if($query->GetItem())
	    {
	      $q->print("<table>\n");
	      foreach my $item ($query->GetItem())
		{
		  my $jid = $item->GetJID();
		  my $node = $item->GetNode();
		  $q->print("<tr>\n");
		  $q->print("<td><a href=\"$me&_host=$jid\">$jid</a></td>");
		  $q->print("<td><a href=\"$me&_host=$jid&_node=$node\">$node</a></td>");
		  $q->print("</tr>\n");
		}
	      $q->print("</table>\n");
	    }

	},last CASE;
    };

  };
if ($@)
  {
    $q->print("<h3>Error</h3>\n<pre>$@</pre>\n");
  }

$q->end();

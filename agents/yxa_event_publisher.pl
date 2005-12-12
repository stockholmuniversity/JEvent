#!/pkg/perl/5.8.6/bin/perl

use Unix::Syslog qw(:macros :subs);
use JEvent;
use Config::IniFiles;
use XML::Simple;

my $prog = $ARGV[0];
my ($buf,$nread,$len);

unless ($prog) {
  $buf = "";
  $nread = sysread STDIN,$buf,2;
  do { syslog(LOG_INFO,"$0: port closed"); exit; } unless $nread == 2;
  $len = unpack "n",$buf;
  $nread = sysread STDIN,$buf,$len;
} else {
  $buf = $prog
}

openlog "yxa/$buf", LOG_PID, LOG_USER;
syslog(LOG_INFO,"starting");
my $ini = Config::IniFiles->new(-file=>'/local/yxa/config/yxa-jevent.ini'); 
my $je = JEvent->new(Config=>$ini);
$je->Connect();
syslog(LOG_INFO,"connected to jevent");

exit if $prog;


# Loves erlang-expr parser
sub split_erlang_list
{
    my %hash;

    my @list = split(/^\{|\},\{|\}$/,shift);
    foreach my $el (@list) {
        $el =~ /^([^,]+),(.*)/ or next;
        $hash{$1} = $2;
    }
    return \%hash;
}

sub _parse_yxa
{
    my ($msg) = @_;
    my $out = {};

    $msg =~ /c=(\w+);\s+id=\"([^\"]+)\";\s+\[(.*)]\s*$/ or return undef;

    my $type = $1;
    my $id = $2;
    my $a = split_erlang_list($3);
    return undef if (!defined $a);

    $id =~ /(.*?)(-UAS.*|-UAC.*|)$/;
    $out->{branch} = $1;

    if ($2 eq "-UAS") {
        $out->{direction} = 1;
    } elsif ($2 eq "-UAC") {
        $out->{direction} = 2;
    } else {
        $out->{direction} = 0;
    }

    if (defined $$a{branch}) {
        $$a{branch} =~ /^\"(.*)\"$/;
        $out->{branch} = $1;
    }
    if (defined $$a{dialog}) {
        $$a{dialog} =~ /^\"(.*)\"$/;
        $out->{dialog} = $1;
    }
    my @u;
    if (defined $$a{to_users}) {
        my @users = split(/^\["|","|"\]$/,$$a{to_users});

        foreach my $e (@users) {
            next if ($e eq "");
            push @u, $e;
        }
    }

    foreach my $k (qw/method response uri to from peer client/) {
      $$a{$k} =~ /^\"(.*)\"$/;
      $out->{$k} = $1;
    }

    if (defined $$a{from_user}) {
        $$a{from_user} =~ /^\"(.*)\"$/;
        push @u, $1;
    }
    if (defined $$a{user}) {
        $$a{user} =~ /^\"(.*)\"$/;
        push @u, $1;
    }
    $out->{users} = \@u;

    foreach my $k (qw/method response uri to from peer client/) {
      $$a{$k} =~ /^\"(.*)\"$/;
      $out->{$k} = $1;
      $out->{$k} =~ s/</&lt\;/og;
      $out->{$k} =~ s/>/&gt\;/og;
    }
    
    return $out;
}
    

for(;;)
  {
    syslog(LOG_DEBUG,"Waiting for event-part");
    $nread = sysread STDIN,$buf,2;
    do { syslog(LOG_INFO,"$0: port closed"); closelog; exit; } unless $nread == 2;
    $len = unpack "n",$buf;
    $nread = sysread STDIN,$buf,$len;

    eval
      {
         my ($level_char) = $buf =~ s/^(.)//o;
         my $level = LOG_DEBUG;
         CASE: {
            $level = LOG_INFO,last CASE if $level_char == 'i';
            $level = LOG_ERR,last CASE if $level_char == 'e';
         }
         my $ref = _parse_yxa($buf);
         my $xml = XMLout($ref,RootName=>'sipevent');
         syslog(LOG_INFO,$xml);
         $je->Publish(Content=>$xml);
      };

    if ($@)
      {
		syslog(LOG_ERR,"$@");
      }
  }

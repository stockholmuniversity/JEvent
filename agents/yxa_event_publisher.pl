#!/usr/local/bin/perl

use Unix::Syslog qw(:macros :subs);
use JEvent;
use Config::IniFiles;
use XML::Simple;

my $buf = "";
my $nread = sysread STDIN,$buf,2;
do { syslog(LOG_INFO,"$0: port closed"); exit; } unless $nread == 2;
my $len = unpack "n",$buf;
$nread = sysread STDIN,$buf,$len;

openlog "yxa/$buf", LOG_PID, LOG_USER;
my $ini = Config::IniFiles->new(-file=>'/local/yxa/config/yxa-jevent.ini'); 
my $je = JEvent->new(Config=>$ini);


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
    my ($host,$program,$pid,$msg) = @_;
    my $out = {};

    $out->{service} = 'sip';

    $msg =~ /c=(\w+);\s+id=\"([^\"]+)\";\s+\[(.*)]\s*$/ or return undef;

    my $type = $1;
    my $id = $2;
    my $a = split_erlang_list($3);
    return undef if (!defined $a);

    $id =~ /(.*?)(-UAS.*|-UAC.*|)$/;
    $out->{caller_id} = $1;

    if ($2 eq "-UAS") {
        $out->{direction} = 1;
    } elsif ($2 eq "-UAC") {
        $out->{direction} = 2;
    } else {
        $out->{direction} = 0;
    }

    if (defined $$a{caller_id}) {
        $$a{caller_id} =~ /^\"(.*)\"$/;
        $out->{caller_id} = $1;
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
    if (defined $$a{from_user}) {
        $$a{from_user} =~ /^\"(.*)\"$/;
        push @u, $1;
    }
    if (defined $$a{user}) {
        $$a{user} =~ /^\"(.*)\"$/;
        push @u, $1;
    }
    $out->{users} = \@u;
    
    if (defined $$a{method}) {
        $$a{method} =~ /^\"(.*)\"$/;
        $out->{method} = "$1";
    }
    if (defined $$a{response}) {
        $$a{response} =~ /^\"(.*)\"$/;
        $out->{response} = $1;
    }
    if (defined $$a{uri}) {
        $$a{uri} =~ /^\"(.*)\"$/;
        $out->{uri} = $1;
    }
    if (defined $$a{to}) {
        $$a{to} =~ /^\"(.*)\"$/;
        $out->{to} = $1;
    }
    if (defined $$a{from}) {
        $$a{from} =~ /^\"(.*)\"$/;
        $out->{from} = $1;
    }
    if (defined $$a{peer}) {
        $$a{peer} =~ /^\"(.*)\"$/;
        $out->{peer} = $1;
    }
    if (defined $$a{client}) {
        $$a{client} =~ /^\"(.*)\"$/;
        $out->{client} = $1;
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
         my $xml = XMLout(_parse_yxa($buf));
         $je->Publish(Content=>$xml);
      };

    if ($@)
      {
		syslog(LOG_ERR,"$@");
      }
  }

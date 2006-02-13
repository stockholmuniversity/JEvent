#!/pkg/perl/5.8.6/bin/perl

use Unix::Syslog qw(:macros :subs);
use Sys::Hostname;
use JEvent;

my $host = hostname;
my $description = $ARGV[0];
my $code = $ARGV[1];

die "Usage: $0 'description' 'return-code' < [check-output]" 
   unless $code;

die "Usage: $0 'description' 'return-code' < [check-output]"
   unless $description;

my $out = "";
while (<STDIN>) {
  $out .= $_;
}

my $je = JEvent->new();
$je->Connect();

$je->Publish(Content=><<EOX);
<nagios:service-check-result xmlns:nagios="http://resource.it.su.se/nagios/NS/1.0" 
                             nagios:description="$description" 
                             nagios:host_name="$host" 
                             nagios:return_code="$code">
<![CDATA[$out]]>
</nagios:service-check-result>
EOX

$je->Disconnect();

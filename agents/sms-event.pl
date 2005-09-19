#!/usr/bin/env perl

use JEvent;

my $type = $ARGV[0];
my $file = $ARGV[1];
my $id   = $ARGV[2];

my $c;

if ($file && -f $file) {
   open SMS,$file
      or die "Unable to open $file: $!\n";
   my $headers = {};
   my @order;
   my $state = 'header';
   my $body = "";

   while (<SMS>) {
      chomp;
      SWITCH: {
         $state eq 'header' && s/([^:]+):\s*(.+)//o and do {
            push(@order,$1);
            $headers->{$1} = $2;
         },last SWITCH;

         $state eq 'header' && /^\s*$/ and do {
            $state = 'body';
         },last SWITCH;

         $state eq 'body' and do {
            $body .= "$_\n";
         },last SWITCH;
      }
   }
   close SMS;

   $c=<<EOC;
      <sms:message>
        <sms:headers>
EOC
   foreach my $h (@order) {
      $c.=<<EOC;
            <sms:header name='$h'>$headers->{$h}</sms:header>
EOC
   }
   $c.=<<EOC;
        </sms:headers>
        <sms:body>[!CDATA[$body]]</sms:body>
      </sms:message>
EOC
}


my $id_attr=" id='$id'" if $id;

my $xml =<<EOX;
<sms xmlns:sms='http://resource.it.su.se/sms/NS/1.0'>
   <sms:event type='$type'$id_attr>
EOX
$xml .= $c if $c;
$xml .=<<EOX;
   </sms:event>
</sms>
EOX

warn $xml;

exit;

$je = JEvent->new();
$je->Connect();

$je->Publish(Node=>'services/sms/it.su.se',Content=>$xml);

$je->Disconnect();

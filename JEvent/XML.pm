package JEvent::XML;

use base 'JEvent';
use XML::Simple;

sub xmlEventCB
{
   my ($self,$sid,$msg) = @_;
 
   my $items = $msg->GetItems();
   return unless $items;
   foreach my $item ($items->GetItems()) {
      my $xml = XMLin($item->GetContent(),ForceArray=>1);
      &{$self->{XEventCB}}($self,$sid,$xml);
   }
}

sub PreExecute
  {
    my $self = shift;

    $self->{EventCB} = \&xmlEventCB if ref $self->{XEventCB} eq 'CODE';
  }

1;

package JEvent::RDF;
use base 'JEvent';

use RDF::Core::Storage::Memory;
use RDF::Core::Model;
use RDF::Core::Model::Parser;
use RDF::Core::Model::Serializer;

sub rdfEventCB
  {
    my ($self,$sid,$msg) = @_;

    my $items = $msg->GetItems();
    return unless $items;
    foreach my $item ($items->GetItems())
      {
	my $model;
	eval
	  {
	    my $storage = RDF::Core::Storage::Memory->new();
	    $model = RDF::Core::Model->new(Storage=>$storage);
	    my %opts = (Model => $model,Source=>$msg->GetXML,SourceType=>'string',BaseURI=>'http://jevent.su.se');
	    my $parser = RDF::Core::Model::Parser->new(%opts);
	    $parser->parse;
	  };
	if ($@)
	  {
	    $self->LogError("Error parsing RDF: \"%s\"\n",$@);
	  }

	if (ref $model)
	  {
	    eval
	      {
		&{$self->{RDFCB}}($self,$model);
	      };
	    if ($@) # retry or die??
	      {
		# XXX
	      }
	  }
      }
  }

sub model
  {
    my $storage = shift || RDF::Core::Storage::Memory->new();
    RDF::Core::Model->new(Storage=>$storage);
  }

sub serialize
  {
    my $xml = "";
    my $s = RDF::Core::Model::Serializer(Model=>$_[1],
					 Output=>\$xml,
					 BaseURI => $_[2] || 'urn:x-jevent:');
    $s->serialize;
    $xml;
  }

sub PreExecute
  {
    my $self = shift;

    $self->{EventCB} = \&rdfEventCB if ref $self->{RDFCB} eq 'CODE';
  }

1;
__END__

=head1 NAME

JEvent::RDF - JEvent for RDF-driven events

=head1 SYNOPSIS

  use JEvent::RDF;

  my $je = JEvent::RDF->new(...
                            RDFCB => sub {
                              my ($self,$model) = @_;

                            });

=head1 DESCRIPTION

The JEvent::RDF agent class extends the base JEvent class by adding a
new type of callback: RDFCB. This overrides the EventCB option (which
cannot be used with JEvent::RDF) and is called with the agent instance
and an instance of RDF::Core::Model, one for each <item/> containing a
valid RDF.


=cut

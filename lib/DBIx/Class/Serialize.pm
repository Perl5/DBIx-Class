package DBIx::Class::Serialize;
use strict;
use Storable qw/freeze thaw/;

sub STORABLE_freeze {
    my ($self,$cloning) = @_;
    return if $cloning;
    my $to_serialize = { %$self };
    delete $to_serialize->{result_source};
    return (freeze($to_serialize));
}

sub STORABLE_thaw {
    my ($self,$cloning,$serialized) = @_;
    %$self = %{ thaw($serialized) };
    no strict 'refs';
    my $class = ${(ref $self) . '::ISA'}[0];
    my $schema = DB->schema;
    $self->result_source($schema->source($class));
}

1;
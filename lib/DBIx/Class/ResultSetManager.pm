package DBIx::Class::ResultSetManager;
use strict;
use base 'DBIx::Class';
use Class::Inspector;

__PACKAGE__->mk_classdata($_) for qw/ base_resultset_class table_resultset_class_suffix /;
__PACKAGE__->base_resultset_class('DBIx::Class::ResultSet');
__PACKAGE__->table_resultset_class_suffix('::_resultset');

sub table {
    my ($self,@rest) = @_;
    $self->next::method(@rest);
    $self->_register_attributes;
    $self->_register_resultset_class;
}

sub load_resultset_components {
    my ($self,@comp) = @_;
    my $resultset_class = $self->_setup_resultset_class;
    $resultset_class->load_components(@comp);
}

sub _register_attributes {
    my $self = shift;
    return unless $self->can('_attr_cache');

    my $cache = $self->_attr_cache;
    foreach my $meth (@{Class::Inspector->methods($self) || []}) {
        my $attrs = $cache->{$self->can($meth)};
        next unless $attrs;
        if ($attrs->[0] eq 'resultset') {
            no strict 'refs';
            my $resultset_class = $self->_setup_resultset_class;
            *{"$resultset_class\::$meth"} = *{"$self\::$meth"};
            undef *{"$self\::$meth"};
        }
    }
}

sub _setup_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->table_resultset_class_suffix;
    no strict 'refs';
    unless (@{"$resultset_class\::ISA"}) {
        @{"$resultset_class\::ISA"} = ($self->base_resultset_class);
    }
    return $resultset_class;
}

sub _register_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->table_resultset_class_suffix;
    no strict 'refs';
    if (@{"$resultset_class\::ISA"}) {
        $self->result_source_instance->resultset_class($resultset_class);        
    } else {
        $self->result_source_instance->resultset_class($self->base_resultset_class);        
    }
}

1;
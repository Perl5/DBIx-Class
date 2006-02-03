package DBIx::Class::ResultSetManager;
use strict;
use base 'DBIx::Class';
use Class::Inspector;

__PACKAGE__->mk_classdata($_) for qw/ _attr_cache custom_resultset_class_suffix /;
__PACKAGE__->_attr_cache({});
__PACKAGE__->custom_resultset_class_suffix('::_rs');

sub base_resultset_class {
    my ($self,$class) = @_;
    $self->result_source_instance->resultset_class($class);
}

sub table {
    my ($self,@rest) = @_;
    $self->next::method(@rest);
    $self->_register_attributes;
}

sub load_resultset_components {
    my ($self,@comp) = @_;
    my $resultset_class = $self->_setup_resultset_class;
    $resultset_class->load_components(@comp);
}

sub MODIFY_CODE_ATTRIBUTES {
    my ($class,$code,@attrs) = @_;
    $class->_attr_cache({ %{$class->_attr_cache}, $code => [@attrs] });
    return ();
}

sub _register_attributes {
    my $self = shift;
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
    $self->_attr_cache(undef);
}

sub _setup_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->custom_resultset_class_suffix;
    no strict 'refs';
    unless (@{"$resultset_class\::ISA"}) {
        @{"$resultset_class\::ISA"} = ($self->result_source_instance->resultset_class);
        $self->result_source_instance->resultset_class($resultset_class);        
    }
    return $resultset_class;
}

1;
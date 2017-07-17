package DBIx::Class::ResultSetManager;
use strict;
use warnings;
use base 'DBIx::Class';

use DBIx::Class::_Util qw( set_subname describe_class_methods );
use namespace::clean;

warn "DBIx::Class::ResultSetManager never left experimental status and
has now been DEPRECATED. This module will be deleted in 09000 so please
migrate any and all code using it to explicit resultset classes using either
__PACKAGE__->resultset_class(...) calls or by switching from using
DBIx::Class::Schema->load_classes() to load_namespaces() and creating
appropriate My::Schema::ResultSet::* classes for it to pick up.";

=head1 NAME

DBIx::Class::ResultSetManager - scheduled for deletion in 09000

=head1 DESCRIPTION

DBIx::Class::ResultSetManager never left experimental status and
has now been DEPRECATED. This module will be deleted in 09000 so please
migrate any and all code using it to explicit resultset classes using either
__PACKAGE__->resultset_class(...) calls or by switching from using
DBIx::Class::Schema->load_classes() to load_namespaces() and creating
appropriate My::Schema::ResultSet::* classes for it to pick up.";

=cut

__PACKAGE__->mk_group_accessors(inherited => qw(
  base_resultset_class table_resultset_class_suffix
));
__PACKAGE__->base_resultset_class('DBIx::Class::ResultSet');
__PACKAGE__->table_resultset_class_suffix('::_resultset');

sub table {
    my ($self,@rest) = @_;
    my $ret = $self->next::method(@rest);
    if (@rest) {
        $self->_register_attributes;
        $self->_register_resultset_class;
    }
    return $ret;
}

sub load_resultset_components {
    my ($self,@comp) = @_;
    my $resultset_class = $self->_setup_resultset_class;
    $resultset_class->load_components(@comp);
}

sub _register_attributes {
    my $self = shift;
    my $cache = $self->_attr_cache;
    return if keys %$cache == 0;

    for my $meth(
      map
        { $_->{name} }
        grep
          { $_->{attributes}{ResultSet} }
          map
            { $_->[0] }
            values %{ describe_class_methods( ref $self || $self )->{methods} }
    ) {
        # This codepath is extremely old, miht as well keep it running
        # as-is with no room for surprises
        no strict 'refs';
        my $resultset_class = $self->_setup_resultset_class;
        my $name = join '::',$resultset_class, $meth;
        *$name = set_subname $name, $self->can($meth);
        delete ${"${self}::"}{$meth};
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
    $self->result_source->resultset_class(
      ( scalar @{"${resultset_class}::ISA"} )
        ? $resultset_class
        : $self->base_resultset_class
    );
}

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;

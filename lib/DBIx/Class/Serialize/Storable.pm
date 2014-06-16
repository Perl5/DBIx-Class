package DBIx::Class::Serialize::Storable;
use strict;
use warnings;

use Storable();
use DBIx::Class::Carp;
use namespace::clean;

carp 'The Serialize::Storable component is now *DEPRECATED*. It has not '
    .'been providing any useful functionality for quite a while, and in fact '
    .'destroys prefetched results in its current implementation. Do not use!';


sub STORABLE_freeze {
    my ($self, $cloning) = @_;
    my $to_serialize = { %$self };

    # Dynamic values, easy to recalculate
    delete $to_serialize->{$_} for qw/related_resultsets _inflated_column/;

    return (Storable::nfreeze($to_serialize));
}

sub STORABLE_thaw {
    my ($self, $cloning, $serialized) = @_;

    %$self = %{ Storable::thaw($serialized) };
}

1;

__END__

=head1 NAME

    DBIx::Class::Serialize::Storable - hooks for Storable nfreeze/thaw

=head1 DEPRECATION NOTE

This component is now B<DEPRECATED>. It has not been providing any useful
functionality for quite a while, and in fact destroys prefetched results
in its current implementation. Do not use!

=head1 SYNOPSIS

    # in a table class definition
    __PACKAGE__->load_components(qw/Serialize::Storable/);

    # meanwhile, in a nearby piece of code
    my $cd = $schema->resultset('CD')->find(12);
    # if the cache uses Storable, this will work automatically
    $cache->set($cd->ID, $cd);

=head1 DESCRIPTION

This component adds hooks for Storable so that result objects can be
serialized. It assumes that your result object class (C<result_class>) is
the same as your table class, which is the normal situation.

=head1 HOOKS

The following hooks are defined for L<Storable> - see the
documentation for L<Storable/Hooks> for detailed information on these
hooks.

=head2 STORABLE_freeze

The serializing hook, called on the object during serialization. It
can be inherited, or defined in the class itself, like any other
method.

=head2 STORABLE_thaw

The deserializing hook called on the object during deserialization.

=head1 AUTHOR AND CONTRIBUTORS

See L<AUTHOR|DBIx::Class/AUTHOR> and L<CONTRIBUTORS|DBIx::Class/CONTRIBUTORS> in DBIx::Class

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

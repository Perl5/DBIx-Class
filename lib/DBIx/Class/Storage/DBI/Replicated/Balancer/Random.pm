package DBIx::Class::Storage::DBI::Replicated::Balancer::Random;

use Moose;
with 'DBIx::Class::Storage::DBI::Replicated::Balancer';
use namespace::clean -except => 'meta';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Balancer::Random - A 'random' Balancer

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.  You
shouldn't need to create instances of this class.
    
=head1 DESCRIPTION

Given a pool (L<DBIx::Class::Storage::DBI::Replicated::Pool>) of replicated
database's (L<DBIx::Class::Storage::DBI::Replicated::Replicant>), defines a
method by which query load can be spread out across each replicant in the pool.

This Balancer uses L<List::Util> keyword 'shuffle' to randomly pick an active
replicant from the associated pool.  This may or may not be random enough for
you, patches welcome.

=head1 ATTRIBUTES

This class defines the following attributes.

=head1 METHODS

This class defines the following methods.

=head2 next_storage

Returns an active replicant at random.  Please note that due to the nature of
the word 'random' this means it's possible for a particular active replicant to
be requested several times in a row.

=cut

sub next_storage {
  my $self = shift @_;
  my @active_replicants = $self->pool->active_replicants;
  my $count_active_replicants = $#active_replicants +1;
  my $random_replicant = int(rand($count_active_replicants));
  
  return $active_replicants[$random_replicant];
}

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;

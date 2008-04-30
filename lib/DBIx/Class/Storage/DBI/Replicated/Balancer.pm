package DBIx::Class::Storage::DBI::Replicated::Balancer;

use Moose;
use List::Util qw(shuffle);

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Balancer; A Software Load Balancer 

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.  You
shouldn't need to create instances of this class.
    
=head1 DESCRIPTION

Given a pool (L<DBIx::Class::Storage::DBI::Replicated::Pool>) of replicated
database's (L<DBIx::Class::Storage::DBI::Replicated::Replicant>), defines a
method by which query load can be spread out across each replicant in the pool.

=head1 ATTRIBUTES

This class defines the following attributes.

=head1 METHODS

This class defines the following methods.

=head2 next_storage ($pool)

Given a pool object, return the next replicant that will serve queries.  The
default behavior is to randomize but you can write your own subclasses of
L<DBIx::Class::Storage::DBI::Replicated::Balancer> to support other balance
systems.

=cut

sub next_storage {
	my $self = shift @_;
	my $pool = shift @_;
	
	return (shuffle($pool->all_replicants))[0];
}


=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
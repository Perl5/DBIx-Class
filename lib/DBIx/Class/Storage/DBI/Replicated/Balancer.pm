package DBIx::Class::Storage::DBI::Replicated::Balancer;

use Moose;

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

=head2 master

The L<DBIx::Class::Storage::DBI> object that is the master database all the
replicants are trying to follow.  The balancer needs to know it since it's the
ultimate fallback.

=cut

has 'master' => (
    is=>'ro',
    isa=>'DBIx::Class::Storage::DBI',
    required=>1,
);

=head2 pool

The L<DBIx::Class::Storage::DBI::Replicated::Pool> object that we are trying to
balance.

=cut

has 'pool' => (
    is=>'ro',
    isa=>'DBIx::Class::Storage::DBI::Replicated::Pool',
    required=>1,
);

=head2 current_replicant

Replicant storages (slaves) handle all read only traffic.  The assumption is
that your database will become readbound well before it becomes write bound
and that being able to spread your read only traffic around to multiple 
databases is going to help you to scale traffic.

This attribute returns the next slave to handle a read request.  Your L</pool>
attribute has methods to help you shuffle through all the available replicants
via it's balancer object.

=cut

has 'current_replicant' => (
    is=> 'rw',
    isa=>'DBIx::Class::Storage::DBI',
    lazy_build=>1,
    handles=>[qw/
        select
        select_single
        columns_info_for
    /],
);

=head1 METHODS

This class defines the following methods.

=head2 _build_current_replicant

Lazy builder for the L</current_replicant_storage> attribute.

=cut

sub _build_current_replicant {
    my $self = shift @_;
    $self->next_storage;
}

=head2 next_storage

Given a pool object, return the next replicant that will serve queries.  The
default behavior is to grap the first replicant it finds but you can write 
your own subclasses of L<DBIx::Class::Storage::DBI::Replicated::Balancer> to 
support other balance systems.

This returns from the pool of active replicants.  If there are no active
replicants, then you should have it return the master as an ultimate fallback.

=cut

sub next_storage {
	my $self = shift @_;
	my $next = ($self->pool->active_replicants)[0];
	return $next ? $next:$self->master;
}

=head2 before: select

Advice on the select attribute.  Each time we use a replicant
we need to change it via the storage pool algorithm.  That way we are spreading
the load evenly (hopefully) across existing capacity.

=cut

before 'select' => sub {
    my $self = shift @_;
    my $next_replicant = $self->next_storage;
    $self->current_replicant($next_replicant);
};

=head2 before: select_single

Advice on the select_single attribute.  Each time we use a replicant
we need to change it via the storage pool algorithm.  That way we are spreading
the load evenly (hopefully) across existing capacity.

=cut

before 'select_single' => sub {
    my $self = shift @_;
    my $next_replicant = $self->next_storage;
    $self->current_replicant($next_replicant);
};

=head2 before: columns_info_for

Advice on the current_replicant_storage attribute.  Each time we use a replicant
we need to change it via the storage pool algorithm.  That way we are spreading
the load evenly (hopefully) across existing capacity.

=cut

before 'columns_info_for' => sub {
    my $self = shift @_;
    my $next_replicant = $self->next_storage;
    $self->current_replicant($next_replicant);
};

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;

package DBIx::Class::Storage::DBI::Replicated::Pool;

use Moose;
use MooseX::AttributeHelpers;
use DBIx::Class::Storage::DBI::Replicated::Replicant;
use List::Util qw(sum);

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Pool; Manage a pool of replicants

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.  You
shouldn't need to create instances of this class.
    
=head1 DESCRIPTION

In a replicated storage type, there is at least one replicant to handle the
read only traffic.  The Pool class manages this replicant, or list of 
replicants, and gives some methods for querying information about their status.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 maximum_lag ($num)

This is a number which defines the maximum allowed lag returned by the
L<DBIx::Class::Storage::DBI/lag_behind_master> method.  The default is 0.  In
general, this should return a larger number when the replicant is lagging
behind it's master, however the implementation of this is database specific, so
don't count on this number having a fixed meaning.  For example, MySQL will
return a number of seconds that the replicating database is lagging.

=cut

has 'maximum_lag' => (
    is=>'rw',
    isa=>'Num',
    required=>1,
    lazy=>1,
    default=>0,
);

=head2 last_validated

This is an integer representing a time since the last time the replicants were
validated. It's nothing fancy, just an integer provided via the perl time 
builtin.

=cut

has 'last_validated' => (
    is=>'rw',
    isa=>'Int',
    reader=>'last_validated',
    writer=>'_last_validated',
    lazy=>1,
    default=>sub {
        time;
    },
);

=head2 replicant_type ($classname)

Base class used to instantiate replicants that are in the pool.  Unless you
need to subclass L<DBIx::Class::Storage::DBI::Replicated::Replicant> you should
just leave this alone.

=cut

has 'replicant_type' => (
    is=>'ro',
    isa=>'ClassName',
    required=>1,
    default=>'DBIx::Class::Storage::DBI',
    handles=>{
    	'create_replicant' => 'new',
    },	
);

=head2 replicants

A hashref of replicant, with the key being the dsn and the value returning the
actual replicant storage.  For example if the $dsn element is something like:

    "dbi:SQLite:dbname=dbfile"
    
You could access the specific replicant via:

    $schema->storage->replicants->{'dbname=dbfile'}
    
This attributes also supports the following helper methods

=over 4

=item set_replicant($key=>$storage)

Pushes a replicant onto the HashRef under $key

=item get_replicant($key)

Retrieves the named replicant

=item has_replicants

Returns true if the Pool defines replicants.

=item num_replicants

The number of replicants in the pool

=item delete_replicant ($key)

removes the replicant under $key from the pool

=back

=cut

has 'replicants' => (
    is=>'rw',
    metaclass => 'Collection::Hash',
    isa=>'HashRef[DBIx::Class::Storage::DBI]',
    default=>sub {{}},
    provides  => {
		'set' => 'set_replicant',
		'get' => 'get_replicant',            
		'empty' => 'has_replicants',
		'count' => 'num_replicants',
		'delete' => 'delete_replicant',
	},
);

=head1 METHODS

This class defines the following methods.

=head2 connect_replicants ($schema, Array[$connect_info])

Given an array of $dsn suitable for connected to a database, create an
L<DBIx::Class::Storage::DBI::Replicated::Replicant> object and store it in the
L</replicants> attribute.

=cut

sub connect_replicants {
	my $self = shift @_;
	my $schema = shift @_;
	
	my @newly_created = ();
	foreach my $connect_info (@_) {
		
		my $replicant = $self->create_replicant($schema);
		$replicant->connect_info($connect_info);	
		$replicant->ensure_connected;
		DBIx::Class::Storage::DBI::Replicated::Replicant->meta->apply($replicant);
		
		my ($key) = ($connect_info->[0]=~m/^dbi\:.+\:(.+)$/);
		$self->set_replicant( $key => $replicant);	
		push @newly_created, $replicant;
	}
	
	return @newly_created;
}

=head2 connected_replicants

Returns true if there are connected replicants.  Actually is overloaded to
return the number of replicants.  So you can do stuff like:

    if( my $num_connected = $storage->has_connected_replicants ) {
    	print "I have $num_connected connected replicants";
    } else {
    	print "Sorry, no replicants.";
    }

This method will actually test that each replicant in the L</replicants> hashref
is actually connected, try not to hit this 10 times a second.

=cut

sub connected_replicants {
	my $self = shift @_;
	return sum( map {
		$_->connected ? 1:0
	} $self->all_replicants );
}

=head2 active_replicants

This is an array of replicants that are considered to be active in the pool.
This does not check to see if they are connected, but if they are not, DBIC
should automatically reconnect them for us when we hit them with a query.

=cut

sub active_replicants {
    my $self = shift @_;
    return ( grep {$_} map {
        $_->active ? $_:0
    } $self->all_replicants );
}

=head2 all_replicants

Just a simple array of all the replicant storages.  No particular order to the
array is given, nor should any meaning be derived.

=cut

sub all_replicants {
    my $self = shift @_;
    return values %{$self->replicants};
}

=head2 validate_replicants

This does a check to see if 1) each replicate is connected (or reconnectable),
2) that is ->is_replicating, and 3) that it is not exceeding the lag amount
defined by L</maximum_lag>.  Replicants that fail any of these tests are set to
inactive, and thus removed from the replication pool.

This tests L<all_replicants>, since a replicant that has been previous marked
as inactive can be reactived should it start to pass the validation tests again.

See L<DBIx::Class::Storage::DBI> for more about checking if a replicating
connection is not following a master or is lagging.

Calling this method will generate queries on the replicant databases so it is
not recommended that you run them very often.

=cut

sub validate_replicants {
    my $self = shift @_;
    foreach my $replicant($self->all_replicants) {
        if(
            $replicant->is_replicating &&
            $replicant->lag_behind_master <= $self->maximum_lag &&
            $replicant->ensure_connected
        ) {
        	## TODO:: Hook debug for this
            $replicant->active(1)
        } else {
        	## TODO:: Hook debug for this
            $replicant->active(0);
        }
    }
    
    ## Mark that we completed this validation.
    $self->_last_validated(time);
}

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;

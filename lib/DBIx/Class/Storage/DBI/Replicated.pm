package DBIx::Class::Storage::DBI::Replicated;

use Moose;
use DBIx::Class::Storage::DBI::Replicated::Pool;

#extends 'DBIx::Class::Storage::DBI', 'Moose::Object';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated - ALPHA Replicated database support

=head1 SYNOPSIS

The Following example shows how to change an existing $schema to a replicated
storage type, add some replicated (readonly) databases, and perform reporting
tasks

    ## Change storage_type in your schema class
    $schema->storage_type( '::DBI::Replicated' );
    
    ## Add some slaves.  Basically this is an array of arrayrefs, where each
    ## arrayref is database connect information
    
    $schema->storage->create_replicants(
        [$dsn1, $user, $pass, \%opts],
        [$dsn1, $user, $pass, \%opts],
        [$dsn1, $user, $pass, \%opts],
        ## This is just going to use the standard DBIC connect method, so it
        ## supports everything that method supports, such as connecting to an
        ## existing database handle.
        [$dbh],
        \%global_opts
    );
    
    ## a hash of replicants, keyed by their DSN
    my %replicants = $schema->storage->replicants;
    my $replicant = $schema->storage->get_replicant($dsn);
    $replicant->status;
    $replicant->is_active;
    $replicant->active;
    
=head1 DESCRIPTION

Warning: This class is marked ALPHA.  We are using this in development and have
some basic test coverage but the code hasn't yet been stressed by a variety
of databases.  Individual DB's may have quirks we are not aware of.  Please
use this in development and pass along your experiences/bug fixes.

This class implements replicated data store for DBI. Currently you can define
one master and numerous slave database connections. All write-type queries
(INSERT, UPDATE, DELETE and even LAST_INSERT_ID) are routed to master
database, all read-type queries (SELECTs) go to the slave database.

Basically, any method request that L<DBIx::Class::Storage::DBI> would normally
handle gets delegated to one of the two attributes: L</master_storage> or to
L</current_replicant_storage>.  Additionally, some methods need to be distributed
to all existing storages.  This way our storage class is a drop in replacement
for L<DBIx::Class::Storage::DBI>.

Read traffic is spread across the replicants (slaves) occuring to a user
selected algorithm.  The default algorithm is random weighted.

TODO more details about the algorithm.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 master

The master defines the canonical state for a pool of connected databases.  All
the replicants are expected to match this databases state.  Thus, in a classic
Master / Slaves distributed system, all the slaves are expected to replicate
the Master's state as quick as possible.  This is the only database in the
pool of databases that is allowed to handle write traffic.

=cut

has 'master' => (
    is=> 'ro',
    isa=>'DBIx::Class::Storage::DBI',
    lazy_build=>1,
    handles=>[qw/   
        on_connect_do
        on_disconnect_do       
        columns_info_for
        connect_info
        throw_exception
        sql_maker
        sqlt_type
        create_ddl_dir
        deployment_statements
        datetime_parser
        datetime_parser_type        
        last_insert_id
        insert
        insert_bulk
        update
        delete
        dbh
        txn_do
        txn_commit
        txn_rollback
        sth
        deploy
    /],
);


=head2 current_replicant

Replicant storages (slaves) handle all read only traffic.  The assumption is
that your database will become readbound well before it becomes write bound
and that being able to spread your read only traffic around to multiple 
databases is going to help you to scale traffic.

This attribute returns the next slave to handle a read request.  Your L</pool>
attribute has methods to help you shuffle through all the available replicants
via it's balancer object.

This attribute defines the following reader/writer methods

=over 4

=item get_current_replicant

Returns the contained L<DBIx::Class::Storage::DBI> replicant

=item set_current_replicant

Set the attribute to a given L<DBIx::Class::Storage::DBI> (or subclass) object.

=back

We split the reader/writer to make it easier to selectively override how the
replicant is altered.

=cut

has 'current_replicant' => (
    is=> 'rw',
    reader=>'get_current_replicant',
    writer=>'set_current_replicant',
    isa=>'DBIx::Class::Storage::DBI',
    lazy_build=>1,
    handles=>[qw/
        select
        select_single
        columns_info_for
    /],
);


=head2 replicant_storage_pool_type

Contains the classname which will instantiate the L</replicant_storage_pool>
object.  Defaults to: L<DBIx::Class::Storage::DBI::Replicated::Pool>.

=cut

has 'replicant_storage_pool_type' => (
    is=>'ro',
    isa=>'ClassName',
    required=>1,
    default=>'DBIx::Class::Storage::DBI::Replicated::Pool',
    handles=> {
    	'create_replicant_storage_pool' => 'new',
    },
);


=head2 pool_balancer_type

The replication pool requires a balance class to provider the methods for
choose how to spread the query load across each replicant in the pool.

=cut

has 'pool_balancer_type' => (
    is=>'ro',
    isa=>'ClassName',
    required=>1,
    default=>'DBIx::Class::Storage::DBI::Replicated::Pool::Balancer',
    handles=> {
    	'create_replicant_storage_pool' => 'new',
    },
);


=head2 replicant_storage_pool

Holds the list of connected replicants, their status and other housekeeping or
reporting methods.

=cut

has 'replicant_storage_pool' => (
    is=>'ro',
    isa=>'DBIx::Class::Storage::DBI::Replicated::Pool',
    lazy_build=>1,
    handles=>[qw/replicant_storages/],
);



=head1 METHODS

This class defines the following methods.

=head2 new

Make sure we properly inherit from L<Moose>.

=cut

sub new {
    my $class = shift @_;
    my $obj = $class->SUPER::new(@_);
  
    return $class->meta->new_object(
        __INSTANCE__ => $obj, @_
    );
}

=head2 _build_master_storage

Lazy builder for the L</master_storage> attribute.

=cut

sub _build_next_replicant_storage {
	DBIx::Class::Storage::DBI->new;
}


=head2 _build_current_replicant_storage

Lazy builder for the L</current_replicant_storage> attribute.

=cut

sub _build_current_replicant_storage {
    shift->replicant_storage_pool->first;
}


=head2 _build_replicant_storage_pool

Lazy builder for the L</replicant_storage_pool> attribute.

=cut

sub _build_replicant_storage_pool {
    my $self = shift @_;
    $self->create_replicant_storage_pool;
}


=head2 around: create_replicant_storage_pool

Make sure all calles to the method set a default balancer type to our current
balancer type.

=cut

around 'create_replicant_storage_pool' => sub {
    my ($method, $self, @args) = @_;
    return $self->$method(balancer_type=>$self->pool_balancer_type, @args);
}


=head2 after: get_current_replicant_storage

Advice on the current_replicant_storage attribute.  Each time we use a replicant
we need to change it via the storage pool algorithm.  That way we are spreading
the load evenly (hopefully) across existing capacity.

=cut

after 'get_current_replicant_storage' => sub {
    my $self = shift @_;
    my $next_replicant = $self->replicant_storage_pool->next;
    $self->next_replicant_storage($next_replicant);
};


=head2 find_or_create

First do a find on the replicant.  If no rows are found, pass it on to the
L</master_storage>

=cut

sub find_or_create {
	my $self = shift @_;
}

=head2 all_storages

Returns an array of of all the connected storage backends.  The first element
in the returned array is the master, and the remainings are each of the
replicants.

=cut

sub all_storages {
	my $self = shift @_;
	
	return (
	   $self->master_storage,
	   $self->replicant_storages,
	);
}


=head2 connected

Check that the master and at least one of the replicants is connected.

=cut

sub connected {
	my $self = shift @_;
	
	return
	   $self->master_storage->connected &&
	   $self->replicant_storage_pool->has_connected_slaves;
}


=head2 ensure_connected

Make sure all the storages are connected.

=cut

sub ensure_connected {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->ensure_connected(@_);
    }
}


=head2 limit_dialect

Set the limit_dialect for all existing storages

=cut

sub limit_dialect {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->name_sep(@_);
    }
}


=head2 quote_char

Set the quote_char for all existing storages

=cut

sub quote_char {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->name_sep(@_);
    }
}


=head2 name_sep

Set the name_sep for all existing storages

=cut

sub name_sep {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->name_sep(@_);
    }
}


=head2 set_schema

Set the schema object for all existing storages

=cut

sub set_schema {
	my $self = shift @_;
	foreach $source (shift->all_sources) {
		$source->set_schema(@_);
	}
}


=head2 debug

set a debug flag across all storages

=cut

sub debug {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->debug(@_);
    }
}


=head2 debugobj

set a debug object across all storages

=cut

sub debugobj {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->debugobj(@_);
    }
}


=head2 debugfh

set a debugfh object across all storages

=cut

sub debugfh {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->debugfh(@_);
    }
}


=head2 debugcb

set a debug callback across all storages

=cut

sub debugcb {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->debugcb(@_);
    }
}


=head2 disconnect

disconnect everything

=cut

sub disconnect {
    my $self = shift @_;
    foreach $source (shift->all_sources) {
        $source->disconnect(@_);
    }
}


=head2 DESTROY

Make sure we pass destroy events down to the storage handlers

=cut

sub DESTROY {
    my $self = shift;
    ## TODO, maybe we can just leave this alone ???
}


=head1 AUTHOR

Norbert Csongrádi <bert@cpan.org>

Peter Siklósi <einon@einon.hu>

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;

__END__

use strict;
use warnings;

use DBIx::Class::Storage::DBI;
use DBD::Multi;

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors( qw/read_source write_source/ );

=head1 NAME

DBIx::Class::Storage::DBI::Replicated - ALPHA Replicated database support

=head1 SYNOPSIS

The Following example shows how to change an existing $schema to a replicated
storage type and update it's connection information to contain a master DSN and
an array of slaves.

    ## Change storage_type in your schema class
    $schema->storage_type( '::DBI::Replicated' );
    
    ## Set your connection.
    $schema->connect(
        $dsn, $user, $password, {
        	AutoCommit => 1,
        	## Other standard DBI connection or DBD custom attributes added as
        	## usual.  Additionally, we have two custom attributes for defining
        	## slave information and controlling how the underlying DBD::Multi
        	slaves_connect_info => [
        	   ## Define each slave like a 'normal' DBI connection, but you add
        	   ## in a DBD::Multi custom attribute to define how the slave is
        	   ## prioritized.  Please see DBD::Multi for more.
        	   [$slave1dsn, $user, $password, {%slave1opts, priority=>10}],
               [$slave2dsn, $user, $password, {%slave2opts, priority=>10}],
               [$slave3dsn, $user, $password, {%slave3opts, priority=>20}],
               ## add in a preexisting database handle
               [$dbh, '','', {priority=>30}], 
               ## DBD::Multi will call this coderef for connects 
               [sub {  DBI->connect(< DSN info >) }, '', '', {priority=>40}],  
               ## If the last item is hashref, we use that for DBD::Multi's 
               ## configuration information.  Again, see DBD::Multi for more.
               {timeout=>25, failed_max=>2},      	   
        	],
        },
    );
    
    ## Now, just use the schema as normal
    $schema->resultset('Table')->find(< unique >); ## Reads will use slaves
    $schema->resultset('Table')->create(\%info); ## Writes will use master

=head1 DESCRIPTION

Warning: This class is marked ALPHA.  We are using this in development and have
some basic test coverage but the code hasn't yet been stressed by a variety
of databases.  Individual DB's may have quirks we are not aware of.  Please
use this in development and pass along your experiences/bug fixes.

This class implements replicated data store for DBI. Currently you can define
one master and numerous slave database connections. All write-type queries
(INSERT, UPDATE, DELETE and even LAST_INSERT_ID) are routed to master
database, all read-type queries (SELECTs) go to the slave database.

For every slave database you can define a priority value, which controls data
source usage pattern. It uses L<DBD::Multi>, so first the lower priority data
sources used (if they have the same priority, the are used randomized), than
if all low priority data sources fail, higher ones tried in order.

=head1 CONFIGURATION

Please see L<DBD::Multi> for most configuration information.

=cut

sub new {
    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self = {};

    bless( $self, $class );

    $self->write_source( DBIx::Class::Storage::DBI->new );
    $self->read_source( DBIx::Class::Storage::DBI->new );

    return $self;
}

sub all_sources {
    my $self = shift;

    my @sources = ($self->read_source, $self->write_source);

    return wantarray ? @sources : \@sources;
}

sub _connect_info {
	my $self = shift;
    my $master = $self->write_source->_connect_info;
    $master->[-1]->{slave_connect_info} = $self->read_source->_connect_info;
    return $master;
}

sub connect_info {
	my ($self, $source_info) = @_;

    ## if there is no $source_info, treat this sub like an accessor
    return $self->_connect_info
     if !$source_info;
    
    ## Alright, let's conect the master 
    $self->write_source->connect_info($source_info);
  
    ## Now, build and then connect the Slaves
    my @slaves_connect_info = @{$source_info->[-1]->{slaves_connect_info}};   
    my $dbd_multi_config = ref $slaves_connect_info[-1] eq 'HASH' 
        ? pop @slaves_connect_info : {};

    ## We need to do this since SQL::Abstract::Limit can't guess what DBD::Multi is
    $dbd_multi_config->{limit_dialect} = $self->write_source->sql_maker->limit_dialect
        unless defined $dbd_multi_config->{limit_dialect};

    @slaves_connect_info = map {
        ## if the first element in the arrayhash is a ref, make that the value
        my $db = ref $_->[0] ? $_->[0] : $_;
    	my $priority = $_->[-1]->{priority} || 10; ## default priority is 10
    	$priority => $db;
    } @slaves_connect_info;
    
    $self->read_source->connect_info([ 
        'dbi:Multi:', undef, undef, { 
        	dsns => [@slaves_connect_info],
        	%$dbd_multi_config,
        },
    ]);
    
    ## Return the formated connection information
    return $self->_connect_info;
}

sub select {
    shift->read_source->select( @_ );
}
sub select_single {
    shift->read_source->select_single( @_ );
}
sub throw_exception {
    shift->read_source->throw_exception( @_ );
}
sub sql_maker {
    shift->read_source->sql_maker( @_ );
}
sub columns_info_for {
    shift->read_source->columns_info_for( @_ );
}
sub sqlt_type {
    shift->read_source->sqlt_type( @_ );
}
sub create_ddl_dir {
    shift->read_source->create_ddl_dir( @_ );
}
sub deployment_statements {
    shift->read_source->deployment_statements( @_ );
}
sub datetime_parser {
    shift->read_source->datetime_parser( @_ );
}
sub datetime_parser_type {
    shift->read_source->datetime_parser_type( @_ );
}
sub build_datetime_parser {
    shift->read_source->build_datetime_parser( @_ );
}

sub limit_dialect { $_->limit_dialect( @_ ) for( shift->all_sources ) }
sub quote_char { $_->quote_char( @_ ) for( shift->all_sources ) }
sub name_sep { $_->quote_char( @_ ) for( shift->all_sources ) }
sub disconnect { $_->disconnect( @_ ) for( shift->all_sources ) }
sub set_schema { $_->set_schema( @_ ) for( shift->all_sources ) }

sub DESTROY {
    my $self = shift;

    undef $self->{write_source};
    undef $self->{read_sources};
}

sub last_insert_id {
    shift->write_source->last_insert_id( @_ );
}
sub insert {
    shift->write_source->insert( @_ );
}
sub update {
    shift->write_source->update( @_ );
}
sub update_all {
    shift->write_source->update_all( @_ );
}
sub delete {
    shift->write_source->delete( @_ );
}
sub delete_all {
    shift->write_source->delete_all( @_ );
}
sub create {
    shift->write_source->create( @_ );
}
sub find_or_create {
    shift->write_source->find_or_create( @_ );
}
sub update_or_create {
    shift->write_source->update_or_create( @_ );
}
sub connected {
    shift->write_source->connected( @_ );
}
sub ensure_connected {
    shift->write_source->ensure_connected( @_ );
}
sub dbh {
    shift->write_source->dbh( @_ );
}
sub txn_do {
    shift->write_source->txn_do( @_ );
}
sub txn_commit {
    shift->write_source->txn_commit( @_ );
}
sub txn_rollback {
    shift->write_source->txn_rollback( @_ );
}
sub sth {
    shift->write_source->sth( @_ );
}
sub deploy {
    shift->write_source->deploy( @_ );
}
sub _prep_for_execute {
	shift->write_source->_prep_for_execute(@_);
}

sub debugobj {
	shift->write_source->debugobj(@_);
}
sub debug {
    shift->write_source->debug(@_);
}

sub debugfh { shift->_not_supported( 'debugfh' ) };
sub debugcb { shift->_not_supported( 'debugcb' ) };

sub _not_supported {
    my( $self, $method ) = @_;

    die "This Storage does not support $method method.";
}

=head1 SEE ALSO

L<DBI::Class::Storage::DBI>, L<DBD::Multi>, L<DBI>

=head1 AUTHOR

Norbert Csongrádi <bert@cpan.org>

Peter Siklósi <einon@einon.hu>

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;

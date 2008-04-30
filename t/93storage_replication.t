use strict;
use warnings;
use lib qw(t/lib);
use Test::More;
use Data::Dump qw/dump/;

BEGIN {
    eval "use Moose";
    plan $@
        ? ( skip_all => 'needs Moose for testing' )
        : ( tests => 33 );
}

use_ok 'DBIx::Class::Storage::DBI::Replicated::Pool';
use_ok 'DBIx::Class::Storage::DBI::Replicated::Balancer';
use_ok 'DBIx::Class::Storage::DBI::Replicated::Replicant';
use_ok 'DBIx::Class::Storage::DBI::Replicated';

## ----------------------------------------------------------------------------
## Build a class to hold all our required testing data and methods.
## ----------------------------------------------------------------------------

TESTSCHEMACLASS: {

    package DBIx::Class::DBI::Replicated::TestReplication;
   
    use DBICTest;
    use File::Copy;
    use Data::Dump qw/dump/;
    
    use base qw/Class::Accessor::Fast/;
    
    __PACKAGE__->mk_accessors( qw/schema master_path slave_paths/ );

    ## Initialize the object
    
	sub new {
	    my $class = shift @_;
	    my $self = $class->SUPER::new(@_);
	
	    $self->schema( $self->init_schema );
	    $self->master_path("t/var/DBIxClass.db");
	
	    return $self;
	}
    
    ## Get the Schema and set the replication storage type
    
    sub init_schema {
        my $class = shift @_;
        my $schema = DBICTest->init_schema(storage_type=>'::DBI::Replicated');
        return $schema;
    }
    
    ## Return an Array of ArrayRefs where each ArrayRef is suitable to use for
    ## $storage->connect_info to be used for connecting replicants.
    
    sub generate_replicant_connect_info {
    	my $self = shift @_;
        my @dsn = map {
            "dbi:SQLite:${_}";
        } @{$self->slave_paths};
        
        return map { [$_,'','',{}] } @dsn;
    }
    
    ## Do a 'good enough' replication by copying the master dbfile over each of
    ## the slave dbfiles.  If the master is SQLite we do this, otherwise we
    ## just do a one second pause to let the slaves catch up.
    
    sub replicate {
        my $self = shift @_;
        foreach my $slave (@{$self->slave_paths}) {
            copy($self->master_path, $slave);
        }
    }
    
    ## Cleanup after ourselves.  Unlink all gthe slave paths.
    
    sub cleanup {
        my $self = shift @_;
        foreach my $slave (@{$self->slave_paths}) {
            unlink $slave;
        }     
    }
}

## ----------------------------------------------------------------------------
## Create an object and run some tests
## ----------------------------------------------------------------------------

## Thi first bunch of tests are basic, just make sure all the bits are behaving

ok my $replicated = DBIx::Class::DBI::Replicated::TestReplication
    ->new({
        slave_paths=>[
	        "t/var/DBIxClass_slave1.db",
	        "t/var/DBIxClass_slave2.db",    
        ],
    }) => 'Created a replication object';
    
isa_ok $replicated->schema
    => 'DBIx::Class::Schema';
    
isa_ok $replicated->schema->storage
    => 'DBIx::Class::Storage::DBI::Replicated';

ok $replicated->schema->storage->meta
    => 'has a meta object';
    
isa_ok $replicated->schema->storage->master
    => 'DBIx::Class::Storage::DBI';
    
isa_ok $replicated->schema->storage->pool
    => 'DBIx::Class::Storage::DBI::Replicated::Pool';
    
isa_ok $replicated->schema->storage->balancer
    => 'DBIx::Class::Storage::DBI::Replicated::Balancer'; 

ok my @replicant_connects = $replicated->generate_replicant_connect_info
    => 'got replication connect information';

ok my @replicated_storages = $replicated->schema->storage->connect_replicants(@replicant_connects)
    => 'Created some storages suitable for replicants';
    
isa_ok $replicated->schema->storage->current_replicant
    => 'DBIx::Class::Storage::DBI';
    
ok $replicated->schema->storage->pool->has_replicants
    => 'does have replicants';     

is $replicated->schema->storage->num_replicants => 2
    => 'has two replicants';
       
isa_ok $replicated_storages[0]
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';

isa_ok $replicated_storages[1]
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';
    
isa_ok $replicated->schema->storage->replicants->{"t/var/DBIxClass_slave1.db"}
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';

isa_ok $replicated->schema->storage->replicants->{"t/var/DBIxClass_slave2.db"}
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';  

## Add some info to the database

$replicated
    ->schema
    ->populate('Artist', [
        [ qw/artistid name/ ],
        [ 4, "Ozric Tentacles"],
    ]);
                
## Make sure all the slaves have the table definitions

$replicated->replicate;

## Make sure we can read the data.

ok my $artist1 = $replicated->schema->resultset('Artist')->find(4)
    => 'Created Result';

isa_ok $artist1
    => 'DBICTest::Artist';
    
is $artist1->name, 'Ozric Tentacles'
    => 'Found expected name for first result';

## Add some new rows that only the master will have  This is because
## we overload any type of write operation so that is must hit the master
## database.

$replicated
    ->schema
    ->populate('Artist', [
        [ qw/artistid name/ ],
        [ 5, "Doom's Children"],
        [ 6, "Dead On Arrival"],
        [ 7, "Watergate"],
    ]);

## Alright, the database 'cluster' is not in a consistent state.  When we do
## a read now we expect bad news

is $replicated->schema->resultset('Artist')->find(5), undef
    => 'read after disconnect fails because it uses a replicant which we have neglected to "replicate" yet';

## Make sure all the slaves have the table definitions
$replicated->replicate;

## Should find some data now

ok my $artist2 = $replicated->schema->resultset('Artist')->find(5)
    => 'Sync succeed';
    
isa_ok $artist2
    => 'DBICTest::Artist';
    
is $artist2->name, "Doom's Children"
    => 'Found expected name for first result';

## What happens when we disconnect all the replicants?

is $replicated->schema->storage->pool->connected_replicants => 2
    => "both replicants are connected";
    
$replicated->schema->storage->replicants->{"t/var/DBIxClass_slave1.db"}->disconnect;
$replicated->schema->storage->replicants->{"t/var/DBIxClass_slave2.db"}->disconnect;

is $replicated->schema->storage->pool->connected_replicants => 0
    => "both replicants are now disconnected";

## All these should pass, since the database should automatically reconnect

ok my $artist3 = $replicated->schema->resultset('Artist')->find(6)
    => 'Still finding stuff.';
    
isa_ok $artist3
    => 'DBICTest::Artist';
    
is $artist3->name, "Dead On Arrival"
    => 'Found expected name for first result';

is $replicated->schema->storage->pool->connected_replicants => 1
    => "One replicant reconnected to handle the job";

## Delete the old database files
$replicated->cleanup;







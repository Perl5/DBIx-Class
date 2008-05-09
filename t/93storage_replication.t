use strict;
use warnings;
use lib qw(t/lib);
use Test::More;
use DBICTest;

BEGIN {
    eval "use Moose; use Test::Moose";
    plan $@
        ? ( skip_all => 'needs Moose for testing' )
        : ( tests => 50 );
}

use_ok 'DBIx::Class::Storage::DBI::Replicated::Pool';
use_ok 'DBIx::Class::Storage::DBI::Replicated::Balancer';
use_ok 'DBIx::Class::Storage::DBI::Replicated::Replicant';
use_ok 'DBIx::Class::Storage::DBI::Replicated';

=head1 HOW TO USE

    This is a test of the replicated storage system.  This will work in one of
    two ways, either it was try to fake replication with a couple of SQLite DBs
    and creative use of copy, or if you define a couple of %ENV vars correctly
    will try to test those.  If you do that, it will assume the setup is properly
    replicating.  Your results may vary, but I have demonstrated this to work with
    mysql native replication.
    
=cut


## ----------------------------------------------------------------------------
## Build a class to hold all our required testing data and methods.
## ----------------------------------------------------------------------------

TESTSCHEMACLASSES: {

    ## --------------------------------------------------------------------- ##
    ## Create an object to contain your replicated stuff.
    ## --------------------------------------------------------------------- ##
    
    package DBIx::Class::DBI::Replicated::TestReplication;
   
    use DBICTest;
    use base qw/Class::Accessor::Fast/;
    
    __PACKAGE__->mk_accessors( qw/schema/ );

    ## Initialize the object
    
	sub new {
	    my $class = shift @_;
	    my $self = $class->SUPER::new(@_);
	
	    $self->schema( $self->init_schema );
	    return $self;
	}
    
    ## Get the Schema and set the replication storage type
    
    sub init_schema {
        my $class = shift @_;
        
        my $schema = DBICTest->init_schema(
            storage_type=>{
            	'::DBI::Replicated' => {
            		balancer_type=>'::Random',
                    balancer_args=>{
                    	auto_validate_every=>100,
                    },
            	}
            },
            deploy_args=>{
                   add_drop_table => 1,
            },
        );

        return $schema;
    }
    
    sub generate_replicant_connect_info {}
    sub replicate {}
    sub cleanup {}

  
    ## --------------------------------------------------------------------- ##
    ## Subclass for when you are using SQLite for testing, this provides a fake
    ## replication support.
    ## --------------------------------------------------------------------- ##
        
    package DBIx::Class::DBI::Replicated::TestReplication::SQLite;

    use DBICTest;
    use File::Copy;    
    use base 'DBIx::Class::DBI::Replicated::TestReplication';
    
    __PACKAGE__->mk_accessors( qw/master_path slave_paths/ );
    
    ## Set the mastep path from DBICTest
    
	sub new {
	    my $class = shift @_;
	    my $self = $class->SUPER::new(@_);
	
	    $self->master_path( DBICTest->_sqlite_dbfilename );
	    $self->slave_paths([
            "t/var/DBIxClass_slave1.db",
            "t/var/DBIxClass_slave2.db",    
        ]);
        
	    return $self;
	}    
	
    ## Return an Array of ArrayRefs where each ArrayRef is suitable to use for
    ## $storage->connect_info to be used for connecting replicants.
    
    sub generate_replicant_connect_info {
        my $self = shift @_;
        my @dsn = map {
            "dbi:SQLite:${_}";
        } @{$self->slave_paths};
        
        return map { [$_,'','',{AutoCommit=>1}] } @dsn;
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
    
    ## --------------------------------------------------------------------- ##
    ## Subclass for when you are setting the databases via custom export vars
    ## This is for when you have a replicating database setup that you are
    ## going to test against.  You'll need to define the correct $ENV and have
    ## two slave databases to test against, as well as a replication system
    ## that will replicate in less than 1 second.
    ## --------------------------------------------------------------------- ##
        
    package DBIx::Class::DBI::Replicated::TestReplication::Custom; 
    use base 'DBIx::Class::DBI::Replicated::TestReplication';
    
    ## Return an Array of ArrayRefs where each ArrayRef is suitable to use for
    ## $storage->connect_info to be used for connecting replicants.
    
    sub generate_replicant_connect_info { 
        return (
            [$ENV{"DBICTEST_SLAVE0_DSN"}, $ENV{"DBICTEST_SLAVE0_DBUSER"}, $ENV{"DBICTEST_SLAVE0_DBPASS"}, {AutoCommit => 1}],
            [$ENV{"DBICTEST_SLAVE1_DSN"}, $ENV{"DBICTEST_SLAVE1_DBUSER"}, $ENV{"DBICTEST_SLAVE1_DBPASS"}, {AutoCommit => 1}],           
        );
    }
    
    ## pause a bit to let the replication catch up 
    
    sub replicate {
    	sleep 1;
    } 
}

## ----------------------------------------------------------------------------
## Create an object and run some tests
## ----------------------------------------------------------------------------

## Thi first bunch of tests are basic, just make sure all the bits are behaving

my $replicated_class = DBICTest->has_custom_dsn ?
    'DBIx::Class::DBI::Replicated::TestReplication::Custom' :
    'DBIx::Class::DBI::Replicated::TestReplication::SQLite';

ok my $replicated = $replicated_class->new
    => 'Created a replication object';
    
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
    
does_ok $replicated->schema->storage->balancer
    => 'DBIx::Class::Storage::DBI::Replicated::Balancer'; 

ok my @replicant_connects = $replicated->generate_replicant_connect_info
    => 'got replication connect information';

ok my @replicated_storages = $replicated->schema->storage->connect_replicants(@replicant_connects)
    => 'Created some storages suitable for replicants';
    
isa_ok $replicated->schema->storage->balancer->current_replicant
    => 'DBIx::Class::Storage::DBI';
    
ok $replicated->schema->storage->pool->has_replicants
    => 'does have replicants';     

is $replicated->schema->storage->pool->num_replicants => 2
    => 'has two replicants';
       
does_ok $replicated_storages[0]
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';

does_ok $replicated_storages[1]
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';
    
my @replicant_names = keys %{$replicated->schema->storage->replicants};

does_ok $replicated->schema->storage->replicants->{$replicant_names[0]}
    => 'DBIx::Class::Storage::DBI::Replicated::Replicant';

does_ok $replicated->schema->storage->replicants->{$replicant_names[1]}
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

SKIP: {
    ## We can't do this test if we have a custom replicants, since we assume
    ## if there are custom one that you are trying to test a real replicating
    ## system.  See docs above for more.
    
    skip 'Cannot test inconsistent replication since you have a real replication system', 1
     if DBICTest->has_custom_dsn && $ENV{"DBICTEST_SLAVE0_DSN"};
    
	## Alright, the database 'cluster' is not in a consistent state.  When we do
	## a read now we expect bad news    
    is $replicated->schema->resultset('Artist')->find(5), undef
    => 'read after disconnect fails because it uses a replicant which we have neglected to "replicate" yet'; 
}

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
    
$replicated->schema->storage->replicants->{$replicant_names[0]}->disconnect;
$replicated->schema->storage->replicants->{$replicant_names[1]}->disconnect;

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
    
## What happens when we try to select something that doesn't exist?

ok ! $replicated->schema->resultset('Artist')->find(666)
    => 'Correctly failed to find something.';
    
## test the reliable option

TESTRELIABLE: {
	
	$replicated->schema->storage->set_reliable_storage;
	
	ok $replicated->schema->resultset('Artist')->find(2)
	    => 'Read from master 1';
	
	ok $replicated->schema->resultset('Artist')->find(5)
	    => 'Read from master 2';
	    
    $replicated->schema->storage->set_balanced_storage;	    
	    
	ok $replicated->schema->resultset('Artist')->find(3)
        => 'Read from replicant';
}

## Make sure when reliable goes out of scope, we are using replicants again

ok $replicated->schema->resultset('Artist')->find(1)
    => 'back to replicant 1.';
    
ok $replicated->schema->resultset('Artist')->find(2)
    => 'back to replicant 2.';

## set all the replicants to inactive, and make sure the balancer falls back to
## the master.

$replicated->schema->storage->replicants->{$replicant_names[0]}->active(0);
$replicated->schema->storage->replicants->{$replicant_names[1]}->active(0);
    
ok $replicated->schema->resultset('Artist')->find(2)
    => 'Fallback to master';

$replicated->schema->storage->replicants->{$replicant_names[0]}->active(1);
$replicated->schema->storage->replicants->{$replicant_names[1]}->active(1);

ok $replicated->schema->resultset('Artist')->find(2)
    => 'Returned to replicates';
    
## Getting slave status tests

SKIP: {
    ## We skip this tests unless you have a custom replicants, since the default
    ## sqlite based replication tests don't support these functions.
    
    skip 'Cannot Test Replicant Status on Non Replicating Database', 9
     unless DBICTest->has_custom_dsn && $ENV{"DBICTEST_SLAVE0_DSN"};

    $replicated->replicate; ## Give the slaves a chance to catchup.

	ok $replicated->schema->storage->replicants->{$replicant_names[0]}->is_replicating
	    => 'Replicants are replicating';
	    
	is $replicated->schema->storage->replicants->{$replicant_names[0]}->lag_behind_master, 0
	    => 'Replicant is zero seconds behind master';
	    
	## Test the validate replicants
	
	$replicated->schema->storage->pool->validate_replicants;
	
	is $replicated->schema->storage->pool->active_replicants, 2
	    => 'Still have 2 replicants after validation';
	    
	## Force the replicants to fail the validate test by required their lag to
	## be negative (ie ahead of the master!)
	
    $replicated->schema->storage->pool->maximum_lag(-10);
    $replicated->schema->storage->pool->validate_replicants;
    
    is $replicated->schema->storage->pool->active_replicants, 0
        => 'No way a replicant be be ahead of the master';
        
    ## Let's be fair to the replicants again.  Let them lag up to 5
	
    $replicated->schema->storage->pool->maximum_lag(5);
    $replicated->schema->storage->pool->validate_replicants;
    
    is $replicated->schema->storage->pool->active_replicants, 2
        => 'Both replicants in good standing again';	
        
	## Check auto validate
	
	is $replicated->schema->storage->balancer->auto_validate_every, 100
	    => "Got the expected value for auto validate";
	    
		## This will make sure we auto validatge everytime
		$replicated->schema->storage->balancer->auto_validate_every(0);
		
		## set all the replicants to inactive, and make sure the balancer falls back to
		## the master.
		
		$replicated->schema->storage->replicants->{$replicant_names[0]}->active(0);
		$replicated->schema->storage->replicants->{$replicant_names[1]}->active(0);
		
		## Ok, now when we go to run a query, autovalidate SHOULD reconnect
	
	is $replicated->schema->storage->pool->active_replicants => 0
	    => "both replicants turned off";
	    	
	ok $replicated->schema->resultset('Artist')->find(5)
	    => 'replicant reactivated';
	    
	is $replicated->schema->storage->pool->active_replicants => 2
	    => "both replicants reactivated";        
}

## Delete the old database files
$replicated->cleanup;







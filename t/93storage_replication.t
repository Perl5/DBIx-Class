use strict;
use warnings;
use lib qw(t/lib);
use Test::More;
use Data::Dump qw/dump/;

BEGIN {
    eval "use Moose";
    plan $@
        ? ( skip_all => 'needs Moose for testing' )
        : ( tests => 30 );
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
    ## the slave dbfiles.
    
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

ok my @replicated_storages = $replicated->schema->storage->create_replicants(@replicant_connects)
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

$replicated->schema->storage->replicants->{"t/var/DBIxClass_slave1.db"}->disconnect;
$replicated->schema->storage->replicants->{"t/var/DBIxClass_slave2.db"}->disconnect;

ok my $artist3 = $replicated->schema->resultset('Artist')->find(6)
    => 'Still finding stuff.';
    
isa_ok $artist3
    => 'DBICTest::Artist';
    
is $artist3->name, "Dead On Arrival"
    => 'Found expected name for first result';


__END__

## ----------------------------------------------------------------------------
## Build a class to hold all our required testing data and methods.
## ----------------------------------------------------------------------------

TESTSCHEMACLASS: {
	
	package DBIx::Class::DBI::Replicated::TestReplication;

	use DBI;	
	use DBICTest;
	use File::Copy;
	
	## Create a constructor
	
	sub new {
		my $class = shift @_;
		my %params = @_;
		
		my $self = bless {
			db_paths => $params{db_paths},
			dsns => $class->init_dsns(%params),
			schema=>$class->init_schema,
		}, $class;
		
		$self->connect;
		return $self;
	}
	
	## get the DSNs.  We build this up from the list of file paths
	
	sub init_dsns {
		my $class = shift @_;
		my %params = @_;
		my $db_paths = $params{db_paths};

		my @dsn = map {
			"dbi:SQLite:${_}";
		} @$db_paths;
		
		return \@dsn;
	}

	## get the Schema and set the replication storage type
	
	sub init_schema {
		my $class = shift @_;
		my $schema = DBICTest->init_schema();
		$schema->storage_type( '::DBI::Replicated' );
		
		return $schema;
	}
	
	## connect the Schema
	
	sub connect {
		my $self = shift @_;
		my ($master, @slaves) = @{$self->{dsns}};
		my $master_connect_info = [$master, '','', {AutoCommit=>1, PrintError=>0}];
		
		my @slavesob;
		foreach my $slave (@slaves)
		{
			my $dbh = shift @{$self->{slaves}}
			 || DBI->connect($slave,"","",{PrintError=>0, PrintWarn=>0});
			
			push @{$master_connect_info->[-1]->{slaves_connect_info}},
			 [$dbh, '','',{priority=>10}];
			 
			push @slavesob,
			 $dbh;
		}
		
		## Keep track of the created slave databases
		$self->{slaves} = \@slavesob;
		
		$self
			->{schema}
			->connect(@$master_connect_info);
	}
	
	## replication
	
	sub replicate {
		my $self = shift @_;
		my ($master, @slaves) = @{$self->{db_paths}};
		
		foreach my $slave (@slaves) {
			copy($master, $slave);
		}
	}
	
	## Cleanup afer ourselves.
	
	sub cleanup {
		my $self = shift @_;
		my ($master, @slaves) = @{$self->{db_paths}};
		
		foreach my $slave (@slaves) {
			unlink $slave;
		}		
	}
	
	## Force a reconnection
	
	sub reconnect {
		my $self = shift @_;
		my $schema = $self->connect;
		$self->{schema} = $schema;
		return $schema;
	}
}

## ----------------------------------------------------------------------------
## Create an object and run some tests
## ----------------------------------------------------------------------------

my %params = (
	db_paths => [
		"t/var/DBIxClass.db",
		"t/var/DBIxClass_slave1.db",
		"t/var/DBIxClass_slave2.db",
	],
);

ok my $replicate = DBIx::Class::DBI::Replicated::TestReplication->new(%params)
	=> 'Created a replication object';
	
isa_ok $replicate->{schema}
	=> 'DBIx::Class::Schema';

## Add some info to the database

$replicate
	->{schema}
	->populate('Artist', [
		[ qw/artistid name/ ],
		[ 4, "Ozric Tentacles"],
	]);
			    
## Make sure all the slaves have the table definitions

$replicate->replicate;

## Make sure we can read the data.

ok my $artist1 = $replicate->{schema}->resultset('Artist')->find(4)
	=> 'Created Result';

isa_ok $artist1
	=> 'DBICTest::Artist';
	
is $artist1->name, 'Ozric Tentacles'
	=> 'Found expected name for first result';

## Add some new rows that only the master will have  This is because
## we overload any type of write operation so that is must hit the master
## database.

$replicate
	->{schema}
	->populate('Artist', [
		[ qw/artistid name/ ],
		[ 5, "Doom's Children"],
		[ 6, "Dead On Arrival"],
		[ 7, "Watergate"],
	]);
	
## Reconnect the database
$replicate->reconnect;

## Alright, the database 'cluster' is not in a consistent state.  When we do
## a read now we expect bad news

is $replicate->{schema}->resultset('Artist')->find(5), undef
	=> 'read after disconnect fails because it uses slave 1 which we have neglected to "replicate" yet';

## Make sure all the slaves have the table definitions
$replicate->replicate;

## Should find some data now

ok my $artist2 = $replicate->{schema}->resultset('Artist')->find(5)
	=> 'Sync succeed';
	
isa_ok $artist2
	=> 'DBICTest::Artist';
	
is $artist2->name, "Doom's Children"
	=> 'Found expected name for first result';
	
## What happens when we delete one of the slaves?

ok my $slave1 = @{$replicate->{slaves}}[0]
	=> 'Got Slave1';

ok $slave1->disconnect
	=> 'disconnected slave1';

$replicate->reconnect;

ok my $artist3 = $replicate->{schema}->resultset('Artist')->find(6)
	=> 'Still finding stuff.';
	
isa_ok $artist3
	=> 'DBICTest::Artist';
	
is $artist3->name, "Dead On Arrival"
	=> 'Found expected name for first result';
	
## Let's delete all the slaves

ok my $slave2 = @{$replicate->{slaves}}[1]
	=> 'Got Slave2';

ok $slave2->disconnect
	=> 'Disconnected slave2';

$replicate->reconnect;

## We expect an error now, since all the slaves are dead

eval {
	$replicate->{schema}->resultset('Artist')->find(4)->name;
};

ok $@ => 'Got error when trying to find artistid 4';

## This should also be an error

eval {
	my $artist4 = $replicate->{schema}->resultset('Artist')->find(7);	
};

ok $@ => 'Got read errors after everything failed';

## make sure ->connect_info returns something sane

ok $replicate->{schema}->storage->connect_info
    => 'got something out of ->connect_info';

## Force a connection to the write source for testing.

$replicate->{schema}->storage($replicate->{schema}->storage->write_source);

## What happens when we do a find for something that doesn't exist?

ok ! $replicate->{schema}->resultset('Artist')->find(666)
    => 'Correctly did not find a bad artist id';

## Delete the old database files
$replicate->cleanup;







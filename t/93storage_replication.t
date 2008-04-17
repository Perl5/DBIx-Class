use strict;
use warnings;
use lib qw(t/lib);
use Test::More;
use Data::Dump qw/dump/;

BEGIN {
    eval "use DBD::Multi";
    plan $@
        ? ( skip_all => 'needs DBD::Multi for testing' )
        : ( tests => 18 );
}	

## ----------------------------------------------------------------------------
## Build a class to hold all our required testing data and methods.
## ----------------------------------------------------------------------------

TESTSCHEMACLASS: {
	
	package DBIx::Class::DBI::Replication::TestReplication;

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
		$schema->storage_type( '::DBI::Replication' );
		
		return $schema;
	}
	
	## connect the Schema
	
	sub connect {
		my $self = shift @_;
		my ($master, @slaves) = @{$self->{dsns}};
		my @connections = ([$master, '','', {AutoCommit=>1, PrintError=>0}]);
		my @slavesob;
		
		foreach my $slave (@slaves)
		{
			my $dbh = shift @{$self->{slaves}}
			 || DBI->connect($slave,"","",{PrintError=>0, PrintWarn=>0});
			
			push @connections,
			 [$dbh, '','',{priority=>10}];
			 
			push @slavesob,
			 $dbh;
		}
		
		## Keep track of the created slave databases
		$self->{slaves} = \@slavesob;
		
		$self
			->{schema}
			->connect([
				@connections,
				{limit_dialect => 'LimitXY'}
			]);
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

ok my $replicate = DBIx::Class::DBI::Replication::TestReplication->new(%params)
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

use Fcntl qw (:flock);

my $master_path = $replicate->{db_paths}->[0];
open LOCKFILE, ">>$master_path"
 or die "Cannot open $master_path";
flock(LOCKFILE, LOCK_EX);

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

## Delete the old database files
$replicate->cleanup;







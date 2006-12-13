use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $dbuser, $dbpass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

$dsn 	= 'dbi:Pg:dbname=postgres;host=localhost' unless $dsn;
$dbuser	= 'postgres' unless $dbuser;
$dbpass	= 'postgres' unless $dbpass;

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $dbuser);
  
plan tests => 3;

DBICTest::Schema->compose_connection('PGTest' => $dsn, $dbuser, $dbpass);

my $dbh = PGTest->schema->storage->dbh;

$dbh->do(qq[

	CREATE TABLE artist
	(
		artistid		serial	NOT NULL	PRIMARY KEY,
		media			bytea	NOT NULL,
		name			varchar NULL
	);
],{ RaiseError => 1, PrintError => 1 });


PGTest::Artist->load_components(qw/ 

	PK::Auto 
	Core 
/);

PGTest::Artist->add_columns(
	
	"media", { 
	
		data_type => "bytea", 
		is_nullable => 0, 
	},
);

# test primary key handling
my $big_long_string	= 'abcd' x 250000;

my $new = PGTest::Artist->create({ media => $big_long_string });

ok($new->artistid, "Created a blob row");
is($new->media, 	$big_long_string, "Set the blob correctly.");

my $rs = PGTest::Artist->find({artistid=>$new->artistid});

is($rs->get_column('media'), $big_long_string, "Created the blob correctly.");

$dbh->do("DROP TABLE artist");




use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $dbuser, $dbpass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $dbuser);
  
plan tests => 3;

my $schema = DBICTest::Schema->connection($dsn, $dbuser, $dbpass, { AutoCommit => 1 });

my $dbh = $schema->storage->dbh;

{
    local $SIG{__WARN__} = sub {};
    $dbh->do('DROP TABLE IF EXISTS artist');

    # the blob/clob are for reference only, will be useful when we switch to SQLT and can test Oracle along the way
    $dbh->do(qq[
        CREATE TABLE bindtype_test 
        (
            id              serial       NOT NULL   PRIMARY KEY,
            bytea           bytea        NULL,
            blob            bytea        NULL,
            clob            text         NULL
        );
    ],{ RaiseError => 1, PrintError => 1 });
}

# test primary key handling
my $big_long_string	= 'abcd' x 250000;

my $new = $schema->resultset('BindType')->create({ bytea => $big_long_string });

ok($new->id, "Created a bytea row");
is($new->bytea, 	$big_long_string, "Set the blob correctly.");

my $rs = $schema->resultset('BindType')->find({ id => $new->id });

is($rs->get_column('bytea'), $big_long_string, "Created the blob correctly.");

$dbh->do("DROP TABLE bindtype_test");




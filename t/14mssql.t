use lib qw(lib t/lib);
use DBICTest::Schema;

use Test::More;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all, 'Set $ENV{DBICTEST_MSSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn);

plan tests => 1;

DBICTest::Schema->compose_connection('MSSQLTest' => $dsn, $user, $pass);

my $dbh = MSSQLTest::Artist->storage->dbh;

$dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL
    DROP TABLE artist");

$dbh->do("CREATE TABLE artist (artistid INT IDENTITY PRIMARY KEY, name VARCHAR(255));");

MSSQLTest::Artist->load_components('PK::Auto::MSSQL');

my $new = MSSQLTest::Artist->create({ name => 'foo' });

ok($new->artistid, "Auto-PK worked");

1;

use lib qw(lib t/lib);
use DBICTest::Schema;

use Test::More;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

warn "$dsn $user $pass";

plan skip_all, 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 1;

DBICTest::Schema->compose_connection('PgTest' => $dsn, $user, $pass);

my $dbh = PgTest::Artist->storage->dbh;

eval {
  $dbh->do("DROP TABLE artist;");
};

$dbh->do("CREATE TABLE artist (artistid serial PRIMARY KEY, name VARCHAR(255));");

PgTest::Artist->load_components('PK::Auto::Pg');

my $new = PgTest::Artist->create({ name => 'foo' });

ok($new->artistid, "Auto-PK worked");

1;

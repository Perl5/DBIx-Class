use lib qw(lib t/lib);
use DBICTest::Schema;

use Test::More;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all, 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 1;

DBICTest::Schema->compose_connection('MySQLTest' => $dsn, $user, $pass);

my $dbh = MySQLTest::Artist->storage->dbh;

$dbh->do("DROP TABLE IF EXISTS artist;");

$dbh->do("CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255));");

#'dbi:mysql:host=localhost;database=dbic_test', 'dbic_test', '');

MySQLTest::Artist->load_components('PK::Auto::MySQL');

my $new = MySQLTest::Artist->create({ name => 'foo' });

ok($new->artistid, "Auto-PK worked");

1;

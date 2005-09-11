use lib qw(lib t/lib);
use DBICTest::Schema;

use Test::More;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all, 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 4;

DBICTest::Schema->compose_connection('MySQLTest' => $dsn, $user, $pass);

my $dbh = MySQLTest::Artist->storage->dbh;

$dbh->do("DROP TABLE IF EXISTS artist;");

$dbh->do("CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255));");

#'dbi:mysql:host=localhost;database=dbic_test', 'dbic_test', '');

MySQLTest::Artist->load_components('PK::Auto::MySQL');

# test primary key handling
my $new = MySQLTest::Artist->create({ name => 'foo' });
ok($new->artistid, "Auto-PK worked");

# test LIMIT support
for (1..6) {
    MySQLTest::Artist->create({ name => 'Artist ' . $_ });
}
my $it = MySQLTest::Artist->search( {},
    { rows => 3,
      offset => 2,
      order_by => 'artistid' }
);
is( $it->count, 3, "LIMIT count ok" );
is( $it->next->name, "Artist 2", "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

# clean up our mess
$dbh->do("DROP TABLE artist");

1;

sub run_tests {
my $schema = shift;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all, 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  . ' (note: creates and drops a table named artist!)' unless ($dsn && $user);

plan tests => 2;

DBICTest::Schema->compose_connection('PgTest' => $dsn, $user, $pass);

my $dbh = PgTest::Artist->storage->dbh;

$dbh->do("CREATE TABLE artist (artistid serial PRIMARY KEY, name VARCHAR(255));");

PgTest::Artist->load_components('PK::Auto::Pg');

my $new = PgTest::Artist->create({ name => 'foo' });

is($new->artistid, 1, "Auto-PK worked");

$new = PgTest::Artist->create({ name => 'bar' });

is($new->artistid, 2, "Auto-PK worked");

$dbh->do("DROP TABLE artist;");

}

1;

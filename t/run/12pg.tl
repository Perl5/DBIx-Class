sub run_tests {
my $schema = shift;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all, 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  . ' (note: creates and drops a table named artist!)' unless ($dsn && $user);

plan tests => 3;

DBICTest::Schema->compose_connection('PgTest' => $dsn, $user, $pass);

my $dbh = PgTest->schema->storage->dbh;

$dbh->do("CREATE TABLE artist (artistid serial PRIMARY KEY, name VARCHAR(255));");

PgTest::Artist->load_components('PK::Auto::Pg');

my $new = PgTest::Artist->create({ name => 'foo' });

is($new->artistid, 1, "Auto-PK worked");

$new = PgTest::Artist->create({ name => 'bar' });

is($new->artistid, 2, "Auto-PK worked");

my $test_type_info = {
    'artistid' => {
        'data_type' => 'int4',
        'is_nullable' => 1,
        'size' => 10
    },
    'name' => {
        'data_type' => 'text',
        'is_nullable' => 1,
        'size' => 4096
    }
};

my $type_info = PgTest->schema->storage->columns_info_for('artist');
is_deeply($type_info, $test_type_info, 'columns_info_for - column data types');

$dbh->do("DROP TABLE artist;");

}

1;

use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 5;

DBICTest::Schema->compose_connection('MySQLTest' => $dsn, $user, $pass);

my $dbh = MySQLTest->schema->storage->dbh;

$dbh->do("DROP TABLE IF EXISTS artist;");

$dbh->do("CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255), charfield CHAR(10));");

#'dbi:mysql:host=localhost;database=dbic_test', 'dbic_test', '');

MySQLTest::Artist->load_components('PK::Auto');

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

my $test_type_info = {
    'artistid' => {
        'data_type' => 'INT',
        'is_nullable' => 0,
        'size' => 11,
        'default_value' => undef,
    },
    'name' => {
        'data_type' => 'VARCHAR',
        'is_nullable' => 1,
        'size' => 255,
        'default_value' => undef,
    },
    'charfield' => {
        'data_type' => 'VARCHAR',
        'is_nullable' => 1,
        'size' => 10,
        'default_value' => undef,
    },
};


my $type_info = MySQLTest->schema->storage->columns_info_for('artist');
is_deeply($type_info, $test_type_info, 'columns_info_for - column data types');



# clean up our mess
$dbh->do("DROP TABLE artist");


use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn);

plan tests => 4;

my $storage_type = '::DBI::MSSQL';
$storage_type = '::DBI::Sybase::MSSQL' if $dsn =~ /^dbi:Sybase:/;
# Add more for others in the future when they exist (ODBC? ADO? JDBC?)

my $schema = DBICTest::Schema->clone;
$schema->storage_type($storage_type);
$schema->connection($dsn, $user, $pass);

my $dbh = $schema->storage->dbh;

$dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL
    DROP TABLE artist");

$dbh->do("CREATE TABLE artist (artistid INT IDENTITY PRIMARY KEY, name VARCHAR(255));");

# Just to test compat shim, Auto is in Core
$schema->class('Artist')->load_components('PK::Auto::MSSQL');

# Test PK
my $new = $schema->resultset('Artist')->create( { name => 'foo' } );
ok($new->artistid, "Auto-PK worked");

# Test LIMIT
for (1..6) {
    $schema->resultset('Artist')->create( { name => 'Artist ' . $_ } );
}

my $it = $schema->resultset('Artist')->search( { },
    { rows     => 3,
      offset   => 2,
      order_by => 'artistid'
    }
);

is( $it->count, 3, "LIMIT count ok" );
ok( $it->next->name, "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

# clean up our mess
END {
    $dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL DROP TABLE artist")
        if $dbh;
}

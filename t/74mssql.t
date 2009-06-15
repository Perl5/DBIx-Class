use strict;
use warnings;  

# use this if you keep a copy of DBD::Sybase linked to FreeTDS somewhere else
BEGIN {
  if (my $lib_dirs = $ENV{DBICTEST_MSSQL_PERL5LIB}) {
    unshift @INC, $_ for split /:/, $lib_dirs;
  }
}

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn);

plan tests => 6;

my $schema = DBICTest::Schema->clone;
$schema->connection($dsn, $user, $pass);

my $dbh = $schema->storage->dbh;

isa_ok($schema->storage, 'DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server');

$dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL
    DROP TABLE artist");
$dbh->do("IF OBJECT_ID('cd', 'U') IS NOT NULL
    DROP TABLE cd");

$dbh->do("CREATE TABLE artist (artistid INT IDENTITY PRIMARY KEY, name VARCHAR(100), rank INT DEFAULT '13', charfield CHAR(10) NULL);");
$dbh->do("CREATE TABLE cd (cdid INT IDENTITY PRIMARY KEY, artist INT,  title VARCHAR(100), year VARCHAR(100), genreid INT NULL, single_track INT NULL);");
# Just to test compat shim, Auto is in Core
$schema->class('Artist')->load_components('PK::Auto::MSSQL');

# Test PK
my $new = $schema->resultset('Artist')->create( { name => 'foo' } );
ok($new->artistid, "Auto-PK worked");

# Test LIMIT
for (1..6) {
    $schema->resultset('Artist')->create( { name => 'Artist ' . $_, rank => $_ } );
}

my $it = $schema->resultset('Artist')->search( { },
    { rows     => 3,
      offset   => 2,
      order_by => 'artistid'
    }
);

# Test ? in data don't get treated as placeholders
my $cd = $schema->resultset('CD')->create( {
    artist      => 1,
    title       => 'Does this break things?',
    year        => 2007,
} );
ok($cd->id, 'Not treating ? in data as placeholders');

is( $it->count, 3, "LIMIT count ok" );
ok( $it->next->name, "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

# clean up our mess
END {
    $dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL DROP TABLE artist")
        if $dbh;
    $dbh->do("IF OBJECT_ID('cd', 'U') IS NOT NULL DROP TABLE cd")
        if $dbh;
}

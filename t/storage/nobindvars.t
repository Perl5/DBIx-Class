use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::DebugObj;
use DBIC::SqlMakerTest;
use DBI::Const::GetInfoType;

{ # Fake storage driver for SQLite + no bind variables
  package DBICTest::SQLite::NoBindVars;
    use Class::C3;
    use base qw/
        DBIx::Class::Storage::DBI::NoBindVars
        DBIx::Class::Storage::DBI::SQLite
    /;
}

my $schema = DBICTest->init_schema (storage_type => 'DBICTest::SQLite::NoBindVars', no_populate => 1);

# test primary key handling
my $new = $schema->resultset('Artist')->create({ name => 'foo' });
ok($new->artistid, "Auto-PK worked");

# test LIMIT support
for (1..6) {
    $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}
my $it = $schema->resultset('Artist')->search( {},
    { rows => 3,
      offset => 2,
      order_by => 'artistid' }
);

is( $it->count, 3, "LIMIT count ok" );  # ask for 3 rows out of 7 artists

my ($sql, @bind);
my $orig_debugobj = $schema->storage->debugobj;
my $orig_debug = $schema->storage->debug;
$schema->storage->debugobj (DBIC::DebugObj->new (\$sql, \@bind) );
$schema->storage->debug (1);

is( $it->next->name, "Artist 2", "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

is_same_sql_bind (
  $sql,
  \@bind,
  'SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me ORDER BY artistid LIMIT 3 OFFSET 2',
  [],
  'Correctly interpolated SQL'
);

done_testing;

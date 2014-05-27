use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

{ # Fake storage driver for SQLite + no bind variables
  package DBICTest::SQLite::NoBindVars;
  use base qw(
    DBIx::Class::Storage::DBI::NoBindVars
    DBIx::Class::Storage::DBI::SQLite
  );
  use mro 'c3';
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

$schema->is_executed_sql_bind( sub {
  is( $it->next->name, "Artist 2", "iterator->next ok" );
  $it->next;
  $it->next;
  is( $it->next, undef, "next past end of resultset ok" );
}, [
  [ 'SELECT me.artistid, me.name, me.rank, me.charfield FROM artist me ORDER BY artistid LIMIT 3 OFFSET 2' ],
], 'Correctly interpolated SQL' );

done_testing;

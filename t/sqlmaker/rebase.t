use strict;
use warnings;

# test relies on the original default
BEGIN { delete @ENV{qw( DBICTEST_SWAPOUT_SQLAC_WITH )} }

use Test::More;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $base_schema = DBICTest->init_schema(
  no_deploy => 1,
);

my $schema = $base_schema->connect(
  sub {
    $base_schema->storage->dbh
  },
  {
    on_connect_call => [ [ rebase_sqlmaker => 'DBICTest::SQLMRebase' ] ],
  },
);

ok (! $base_schema->storage->connected, 'No connection on base schema yet');
ok (! $schema->storage->connected, 'No connection on experimental schema yet');

$schema->storage->ensure_connected;

is(
  $schema->storage->sql_maker->__select_counter,
  undef,
  "No statements registered yet",
);

is_deeply(
  mro::get_linear_isa( ref( $schema->storage->sql_maker ) ),
  [
    qw(
      DBIx::Class::SQLMaker::SQLite__REBASED_ON__DBICTest::SQLMRebase
      DBIx::Class::SQLMaker::SQLite
      DBIx::Class::SQLMaker
      DBICTest::SQLMRebase
      DBIx::Class::SQLMaker::ClassicExtensions
    ),
    @{ mro::get_linear_isa( 'DBIx::Class' ) },
    @{ mro::get_linear_isa( 'SQL::Abstract::Classic' ) },
  ],
  'Expected SQLM object inheritance after rebase',
);


$schema->resultset('Artist')->count_rs->as_query;

is(
  $schema->storage->sql_maker->__select_counter,
  1,
  "1 SELECT fired off, tickling override",
);


$base_schema->resultset('Artist')->count_rs->as_query;

is(
  ref( $base_schema->storage->sql_maker ),
  'DBIx::Class::SQLMaker::SQLite',
  'Expected core SQLM object on original schema remains',
);

is(
  $schema->storage->sql_maker->__select_counter,
  1,
  "No further SELECTs seen by experimental override",
);


done_testing;

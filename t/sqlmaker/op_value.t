use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;

use_ok('DBICTest');

my $schema = DBICTest->init_schema();

my $sql_maker = $schema->storage->sql_maker;

for my $q ('', '"') {

  $sql_maker->quote_char($q);

  is_same_sql_bind (
    \[ $sql_maker->select ('artist', '*', { arr1 => { -value => [1,2] }, arr2 => { '>', { -value => [3,4] } }, field => [5,6] } ) ],
    "SELECT *
      FROM ${q}artist${q}
      WHERE ${q}arr1${q} = ? AND
            ${q}arr2${q} > ? AND
            ( ${q}field${q} = ? OR ${q}field${q} = ? )
    ",
    [
      [ arr1 => [1,2] ],
      [ arr2 => [3,4] ],
      [ field => 5 ],
      [ field => 6 ],
    ],
  );
}

done_testing;

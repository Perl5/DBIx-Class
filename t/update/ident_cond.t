use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $artist = $schema->resultset('Artist')->next;

is_deeply(
  [ $artist->id, $artist->ident_condition, $artist->_storage_ident_condition ],
  [ 1, { artistid => 1 }, { artistid => 1 } ],
  'Correct identity state of freshly retrieved object',
);

$artist->artistid(888);

is_deeply(
  [ $artist->id, $artist->ident_condition, $artist->_storage_ident_condition ],
  [ 888, { artistid => 888 }, { artistid => 1 } ],
  'Correct identity state of object with modified PK',
);

$artist->update;

is_deeply(
  [ $artist->id, $artist->ident_condition, $artist->_storage_ident_condition ],
  [ 888, { artistid => 888 }, { artistid => 888 } ],
  'Correct identity state after storage update',
);

done_testing;

use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $s = DBICTest->init_schema (no_deploy => 1, );
$s->storage->sql_maker->limit_dialect ('RowNum');

my $rs = $s->resultset ('CD');

is_same_sql_bind (
  $rs->search ({}, { rows => 1, offset => 3,columns => [
      { id => 'foo.id' },
      { 'bar.id' => 'bar.id' },
      { bleh => \ 'TO_CHAR (foo.womble, "blah")' },
    ]})->as_query,
  '(SELECT id, bar__id, bleh
      FROM (
        SELECT id, bar__id, bleh, ROWNUM rownum__index
          FROM (
            SELECT foo.id AS id, bar.id AS bar__id, TO_CHAR(foo.womble, "blah") AS bleh
              FROM cd me
          ) me
      ) me
    WHERE rownum__index BETWEEN 4 AND 4
  )',
  [],
  'Rownum subsel aliasing works correctly'
);

done_testing;

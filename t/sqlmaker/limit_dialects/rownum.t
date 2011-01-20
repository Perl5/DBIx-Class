use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;

my ($TOTAL, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__total_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

my $s = DBICTest->init_schema (no_deploy => 1, );
$s->storage->sql_maker->limit_dialect ('RowNum');

my $rs = $s->resultset ('CD');

is_same_sql_bind (
  $rs->search ({}, { rows => 1, offset => 3,columns => [
      { id => 'foo.id' },
      { 'bar.id' => 'bar.id' },
      { bleh => \ 'TO_CHAR (foo.womble, "blah")' },
    ]})->as_query,
  '(
    SELECT id, bar__id, bleh
      FROM (
        SELECT id, bar__id, bleh, ROWNUM rownum__index
          FROM (
            SELECT foo.id AS id, bar.id AS bar__id, TO_CHAR(foo.womble, "blah") AS bleh
              FROM cd me
          ) me
        WHERE ROWNUM <= ?
      ) me
    WHERE rownum__index >= ?
  )',
  [
    [ $TOTAL => 4 ],
    [ $OFFSET => 4 ],
  ],
  'Rownum subsel aliasing works correctly'
);

is_same_sql_bind (
  $rs->search ({}, { rows => 2, offset => 3,columns => [
      { id => 'foo.id' },
      { 'ends_with_me.id' => 'ends_with_me.id' },
    ]})->as_query,
  '(SELECT id, ends_with_me__id
      FROM (
        SELECT id, ends_with_me__id, ROWNUM rownum__index
          FROM (
            SELECT foo.id AS id, ends_with_me.id AS ends_with_me__id
              FROM cd me
          ) me
        WHERE ROWNUM <= ?
      ) me
    WHERE rownum__index >= ?
  )',
  [
    [ $TOTAL => 5 ],
    [ $OFFSET => 4 ],
  ],
  'Rownum subsel aliasing works correctly'
);

{
  $rs = $s->resultset('Artist')->search({}, {
    columns => 'name',
    offset => 1,
    order_by => 'name',
  });
  local $rs->result_source->{name} = "weird \n newline/multi \t \t space containing \n table";

  like (
    ${$rs->as_query}->[0],
    qr| weird \s \n \s newline/multi \s \t \s \t \s space \s containing \s \n \s table|x,
    'Newlines/spaces preserved in final sql',
  );
}


done_testing;

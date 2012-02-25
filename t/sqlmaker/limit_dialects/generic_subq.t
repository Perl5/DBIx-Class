use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;
my ($ROWS, $TOTAL, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__total_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);


my $schema = DBICTest->init_schema;

$schema->storage->_sql_maker->limit_dialect ('GenericSubQ');

my $rs = $schema->resultset ('BooksInLibrary')->search ({}, {
  '+columns' => [{ owner_name => 'owner.name' }],
  join => 'owner',
  rows => 2,
  order_by => 'me.title',
});

is_same_sql_bind(
  $rs->as_query,
  '(
    SELECT  id, source, owner, title, price,
            owner_name
      FROM (
        SELECT  me.id, me.source, me.owner, me.title, me.price,
                owner.name AS owner_name
          FROM books me
          JOIN owners owner ON owner.id = me.owner
        WHERE ( source = ? )
      ) me
    WHERE
      (
        SELECT COUNT(*)
          FROM books rownum__emulation
        WHERE rownum__emulation.title < me.title
      ) < ?
    ORDER BY me.title
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $ROWS => 2 ],
  ],
);

is_deeply (
  [ $rs->get_column ('title')->all ],
  ['Best Recipe Cookbook', 'Dynamical Systems'],
  'Correct columns selected with rows',
);

$schema->storage->_sql_maker->quote_char ('"');
$schema->storage->_sql_maker->name_sep ('.');

$rs = $schema->resultset ('BooksInLibrary')->search ({}, {
  order_by => { -desc => 'title' },
  '+select' => ['owner.name'],
  '+as' => ['owner.name'],
  join => 'owner',
  rows => 3,
  offset => 1,
});

is_same_sql_bind(
  $rs->as_query,
  '(
    SELECT  "id", "source", "owner", "title", "price",
            "owner__name"
      FROM (
        SELECT  "me"."id", "me"."source", "me"."owner", "me"."title", "me"."price",
                "owner"."name" AS "owner__name"
          FROM "books" "me"
          JOIN "owners" "owner" ON "owner"."id" = "me"."owner"
        WHERE ( "source" = ? )
      ) "me"
    WHERE
      (
        SELECT COUNT(*)
          FROM "books" "rownum__emulation"
        WHERE "rownum__emulation"."title" > "me"."title"
      ) BETWEEN ? AND ?
    ORDER BY "title" DESC
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $OFFSET => 1 ],
    [ $TOTAL => 3 ],
  ],
);

is_deeply (
  [ $rs->get_column ('title')->all ],
  [ 'Dynamical Systems', 'Best Recipe Cookbook' ],
  'Correct columns selected with rows',
);

$rs = $schema->resultset ('BooksInLibrary')->search ({}, {
  order_by => 'title',
  'select' => ['owner.name'],
  'as' => ['owner_name'],
  join => 'owner',
  offset => 1,
});

is_same_sql_bind(
  $rs->as_query,
  '(
    SELECT "owner_name"
      FROM (
        SELECT "owner"."name" AS "owner_name", "title"
          FROM "books" "me"
          JOIN "owners" "owner" ON "owner"."id" = "me"."owner"
        WHERE ( "source" = ? )
      ) "me"
    WHERE
      (
        SELECT COUNT(*)
          FROM "books" "rownum__emulation"
        WHERE "rownum__emulation"."title" < "me"."title"
      ) BETWEEN ? AND ?
    ORDER BY "title"
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $OFFSET => 1 ],
    [ $TOTAL => 2147483647 ],
  ],
);

is_deeply (
  [ $rs->get_column ('owner_name')->all ],
  [ ('Newton') x 2 ],
  'Correct columns selected with rows',
);

{
  $rs = $schema->resultset('Artist')->search({}, {
    columns => 'artistid',
    offset => 1,
    order_by => 'artistid',
  });
  local $rs->result_source->{name} = "weird \n newline/multi \t \t space containing \n table";

  like (
    ${$rs->as_query}->[0],
    qr| weird \s \n \s newline/multi \s \t \s \t \s space \s containing \s \n \s table|x,
    'Newlines/spaces preserved in final sql',
  );
}

done_testing;

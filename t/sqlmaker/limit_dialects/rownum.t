use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my ($TOTAL, $OFFSET, $ROWS) = (
   DBIx::Class::SQLMaker::ClassicExtensions->__total_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__offset_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype,
);

my $s = DBICTest->init_schema (no_deploy => 1, );
$s->storage->sql_maker->limit_dialect ('RowNum');

my $rs = $s->resultset ('CD')->search({ id => 1 });

# important for a test below, never traversed
$rs->result_source->add_relationship(
  ends_with_me => 'DBICTest::Schema::Artist', sub {}
);


my $where_bind = [ { dbic_colname => 'id' }, 1 ];

for my $test_set (
  {
    name => 'Rownum subsel aliasing works correctly',
    rs => $rs->search_rs(undef, {
      rows => 1,
      offset => 3,
      columns => [
        { id => 'foo.id' },
        { 'artist.id' => 'bar.id' },
        { bleh => \'TO_CHAR (foo.womble, "blah")' },
      ]
    }),
    sql => '(
      SELECT id, artist__id, bleh
      FROM (
        SELECT id, artist__id, bleh, ROWNUM AS rownum__index
        FROM (
          SELECT foo.id AS id, bar.id AS artist__id, TO_CHAR (foo.womble, "blah") AS bleh
            FROM cd me
          WHERE id = ?
        ) me
      ) me WHERE rownum__index BETWEEN ? AND ?
    )',
    binds => [
      $where_bind,
      [ $OFFSET => 4 ],
      [ $TOTAL => 4 ],
    ],
  }, {
    name => 'Rownum subsel aliasing works correctly with unique order_by',
    rs => $rs->search_rs(undef, {
      rows => 1,
      offset => 3,
      columns => [
        { id => 'foo.id' },
        { 'artist.id' => 'bar.id' },
        { bleh => \'TO_CHAR (foo.womble, "blah")' },
      ],
      order_by => [qw( artist title )],
    }),
    sql => '(
      SELECT id, artist__id, bleh
      FROM (
        SELECT id, artist__id, bleh, ROWNUM AS rownum__index
        FROM (
          SELECT foo.id AS id, bar.id AS artist__id, TO_CHAR(foo.womble, "blah") AS bleh
            FROM cd me
          WHERE id = ?
          ORDER BY artist, title
        ) me
        WHERE ROWNUM <= ?
      ) me
      WHERE rownum__index >= ?
    )',
    binds => [
      $where_bind,
      [ $TOTAL => 4 ],
      [ $OFFSET => 4 ],
    ],
  },
 {
    name => 'Rownum subsel aliasing works correctly with non-unique order_by',
    rs => $rs->search_rs(undef, {
      rows => 1,
      offset => 3,
      columns => [
        { id => 'foo.id' },
        { 'artist.id' => 'bar.id' },
        { bleh => \'TO_CHAR (foo.womble, "blah")' },
      ],
      order_by => 'artist',
    }),
    sql => '(
      SELECT id, artist__id, bleh
      FROM (
        SELECT id, artist__id, bleh, ROWNUM AS rownum__index
        FROM (
          SELECT foo.id AS id, bar.id AS artist__id, TO_CHAR(foo.womble, "blah") AS bleh
            FROM cd me
          WHERE id = ?
          ORDER BY artist
        ) me
      ) me
      WHERE rownum__index BETWEEN ? and ?
    )',
    binds => [
      $where_bind,
      [ $OFFSET => 4 ],
      [ $TOTAL => 4 ],
    ],
  }, {
    name => 'Rownum subsel aliasing #2 works correctly',
    rs => $rs->search_rs(undef, {
      rows => 2,
      offset => 3,
      columns => [
        { id => 'foo.id' },
        { 'ends_with_me.id' => 'ends_with_me.id' },
      ]
    }),
    sql => '(
      SELECT id, ends_with_me__id
      FROM (
        SELECT id, ends_with_me__id, ROWNUM AS rownum__index
        FROM (
          SELECT foo.id AS id, ends_with_me.id AS ends_with_me__id
            FROM cd me
          WHERE id = ?
        ) me
      ) me WHERE rownum__index BETWEEN ? AND ?
    )',
    binds => [
      $where_bind,
      [ $OFFSET => 4 ],
      [ $TOTAL => 5 ],
    ],
  }, {
    name => 'Rownum subsel aliasing #2 works correctly with unique order_by',
    rs => $rs->search_rs(undef, {
      rows => 2,
      offset => 3,
      columns => [
        { id => 'foo.id' },
        { 'ends_with_me.id' => 'ends_with_me.id' },
      ],
      order_by => [qw( year artist title )],
    }),
    sql => '(
      SELECT id, ends_with_me__id
      FROM (
        SELECT id, ends_with_me__id, ROWNUM AS rownum__index
        FROM (
          SELECT foo.id AS id, ends_with_me.id AS ends_with_me__id
            FROM cd me
          WHERE id = ?
          ORDER BY year, artist, title
        ) me
        WHERE ROWNUM <= ?
      ) me
      WHERE rownum__index >= ?
    )',
    binds => [
      $where_bind,
      [ $TOTAL => 5 ],
      [ $OFFSET => 4 ],
    ],
  }
) {
  is_same_sql_bind(
    $test_set->{rs}->as_query,
    $test_set->{sql},
    $test_set->{binds},
    $test_set->{name});
}

{
my $subq = $s->resultset('Owners')->search({
   'count.id' => { -ident => 'owner.id' },
}, { alias => 'owner' })->count_rs;

my $rs_selectas_rel = $s->resultset('BooksInLibrary')->search ({}, {
  columns => [
     { owner_name => 'owner.name' },
     { owner_books => $subq->as_query },
  ],
  join => 'owner',
  rows => 2,
  offset => 3,
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT owner_name, owner_books
      FROM (
        SELECT owner_name, owner_books, ROWNUM AS rownum__index
          FROM (
            SELECT  owner.name AS owner_name,
              ( SELECT COUNT( * ) FROM owners owner WHERE (count.id = owner.id)) AS owner_books
              FROM books me
              JOIN owners owner ON owner.id = me.owner
            WHERE ( source = ? )
          ) me
      ) me
    WHERE rownum__index BETWEEN ? AND ?
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
      => 'Library' ],
    [ $OFFSET => 4 ],
    [ $TOTAL => 5 ],
  ],

  'pagination with subquery works'
);

}

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

{
my $subq = $s->resultset('Owners')->search({
   'books.owner' => { -ident => 'owner.id' },
}, { alias => 'owner', select => ['id'] } )->count_rs;

my $rs_selectas_rel = $s->resultset('BooksInLibrary')->search( { -exists => $subq->as_query }, { select => ['id','owner'], rows => 1 } );

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT me.id, me.owner FROM (
      SELECT me.id, me.owner  FROM books me WHERE ( ( (EXISTS (SELECT COUNT( * ) FROM owners owner WHERE ( books.owner = owner.id ))) AND source = ? ) )
    ) me
    WHERE ROWNUM <= ?
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' } => 'Library' ],
    [ $ROWS => 1 ],
  ],
  'Pagination with sub-query in WHERE works'
);

}

done_testing;

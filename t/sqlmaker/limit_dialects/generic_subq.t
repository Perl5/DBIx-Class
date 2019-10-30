use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use List::Util 'min';
use DBICTest ':DiffSQL';
my ($ROWS, $TOTAL, $OFFSET) = (
   DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__total_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__offset_bindtype,
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
    SELECT  me.id, me.source, me.owner, me.title, me.price,
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
    ORDER BY me.title ASC
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
    SELECT  "me"."id", "me"."source", "me"."owner", "me"."title", "me"."price",
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
    ORDER BY "me"."title" DESC
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
        SELECT "owner"."name" AS "owner_name", "me"."title"
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
    ORDER BY "me"."title" ASC
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

$rs = $schema->resultset('CD')->search({}, {
  columns => [qw( me.cdid me.title me.genreid me.year tracks.position tracks.title )],
  join => 'tracks',
  collapse => 1,
  order_by => [ { -asc => 'me.genreid' }, { -desc => 'year' }, 'me.title', \ 'single_track DESC', { -desc => [qw( me.cdid tracks.position )] } ],
});

my @full_res = @{$rs->all_hri};

is (@full_res, 5, 'Expected amount of CDs');

is_deeply (
  \@full_res,
  [
    { cdid => 2, genreid => undef, title => "Forkful of bees", year => 2001, tracks => [
      { position => 3, title => "Sticky Honey" },
      { position => 2, title => "Stripy" },
      { position => 1, title => "Stung with Success" },
    ] },
    { cdid => 4, genreid => undef, title => "Generic Manufactured Singles", year => 2001, tracks => [
      { position => 3, title => "No More Ideas" },
      { position => 2, title => "Boring Song" },
      { position => 1, title => "Boring Name" },
    ] },
    { cdid => 5, genreid => undef, title => "Come Be Depressed With Us", year => 1998, tracks => [
      { position => 3, title => "Suicidal" },
      { position => 2, title => "Under The Weather" },
      { position => 1, title => "Sad" },
    ] },
    { cdid => 3, genreid => undef, title => "Caterwaulin' Blues", year => 1997, tracks => [
      { position => 3, title => "Fowlin" },
      { position => 2, title => "Howlin" },
      { position => 1, title => "Yowlin" },
    ] },
    { cdid => 1, genreid => 1, title => "Spoonful of bees", year => 1999, tracks => [
      { position => 3, title => "Beehind You" },
      { position => 2, title => "Apiary" },
      { position => 1, title => "The Bees Knees" },
    ] },
  ],
  'Complex ordered gensubq limited cds and tracks in expected sqlite order'
);

for my $slice (
  [0, 10],
  [3, 5 ],
  [4, 6 ],
  [0, 2 ],
  [1, 3 ],
) {

  my $rownum_cmp_op = $slice->[0]
    ? 'BETWEEN ? AND ?'
    : ' < ?'
  ;

{
  local $TODO = "Temporary workaround until fix of https://twitter.com/dbix_class/status/957271153751527424 proliferates";

  is_deeply(
    $rs->slice(@$slice)->all_hri,
    [ @full_res[ $slice->[0] .. min($#full_res, $slice->[1]) ] ],
    "Expected array slice on complex ordered limited gensubq ($slice->[0] : $slice->[1])",
  );
}

  is_same_sql_bind(
    $rs->slice(@$slice)->as_query,
    qq{(
      SELECT  "me"."cdid", "me"."title", "me"."genreid", "me"."year",
              "tracks"."position", "tracks"."title"
        FROM (
          SELECT "me"."cdid", "me"."title", "me"."genreid", "me"."year", "me"."single_track"
            FROM (
              SELECT "me"."cdid", "me"."title", "me"."genreid", "me"."year", "me"."single_track"
                FROM cd "me"
                LEFT JOIN "track" "tracks"
                  ON "tracks"."cd" = "me"."cdid"
              GROUP BY "me"."cdid", "me"."title", "me"."genreid", "me"."year", "me"."single_track"
             ) "me"
          WHERE (
            SELECT COUNT( * )
              FROM cd "rownum__emulation"
            WHERE (
              ( "me"."genreid" IS NOT NULL AND "rownum__emulation"."genreid" IS NULL )
                OR
              (
                "rownum__emulation"."genreid" < "me"."genreid"
                  AND
                "me"."genreid" IS NOT NULL
                  AND
                "rownum__emulation"."genreid" IS NOT NULL
              )
                OR
              (
                (
                  "me"."genreid" = "rownum__emulation"."genreid"
                    OR
                  ( "me"."genreid" IS NULL AND "rownum__emulation"."genreid" IS NULL )
                )
                  AND
                "rownum__emulation"."year" > "me"."year"
              )
                OR
              (
                (
                  "me"."genreid" = "rownum__emulation"."genreid"
                    OR
                  ( "me"."genreid" IS NULL AND "rownum__emulation"."genreid" IS NULL )
                )
                  AND
                "me"."year" = "rownum__emulation"."year"
                  AND
                "rownum__emulation"."title" < "me"."title"
              )
                OR
              (
                (
                  "me"."genreid" = "rownum__emulation"."genreid"
                    OR
                  ( "me"."genreid" IS NULL AND "rownum__emulation"."genreid" IS NULL )
                )
                  AND
                "me"."year" = "rownum__emulation"."year"
                  AND
                "me"."title" = "rownum__emulation"."title"
                  AND
                (
                  ("me"."single_track" IS NULL AND "rownum__emulation"."single_track" IS NOT NULL )
                    OR
                  (
                    "rownum__emulation"."single_track" > "me"."single_track"
                      AND
                    "me"."single_track" IS NOT NULL
                      AND
                    "rownum__emulation"."single_track" IS NOT NULL
                  )
                )
              )
                OR
              (
                (
                  "me"."genreid" = "rownum__emulation"."genreid"
                    OR
                  ( "me"."genreid" IS NULL AND "rownum__emulation"."genreid" IS NULL )
                )
                AND
                "me"."year" = "rownum__emulation"."year"
                  AND
                "me"."title" = "rownum__emulation"."title"
                  AND
                (
                  ( "me"."single_track" = "rownum__emulation"."single_track" )
                    OR
                  ( "me"."single_track" IS NULL AND "rownum__emulation"."single_track" IS NULL )
                )
                  AND
                "rownum__emulation"."cdid" > "me"."cdid"
              )
            )
          ) $rownum_cmp_op
          ORDER BY "me"."genreid" ASC, "me"."year" DESC, "me"."title" ASC, "me"."single_track" DESC, "me"."cdid" DESC
        ) "me"
        LEFT JOIN "track" "tracks"
          ON "tracks"."cd" = "me"."cdid"
      ORDER BY "me"."genreid" ASC, "year" DESC, "me"."title", single_track DESC, "me"."cdid" DESC, "tracks"."position" DESC
    )},
    [
      ( $slice->[0] ? [ $OFFSET => $slice->[0] ] : () ),
      [ $TOTAL => $slice->[1] + ($slice->[0] ? 0 : 1 ) ],
    ],
    "Expected sql on complex ordered limited gensubq ($slice->[0] : $slice->[1])",
  );
}

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

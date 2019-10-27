use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use List::Util 'min';

use DBICTest ':DiffSQL';

my ($ROWS, $OFFSET) = (
   DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__offset_bindtype,
);

my $schema = DBICTest->init_schema(quote_names => 1);

my $artist_rs = $schema->resultset('Artist');

my $filtered_cd_rs = $artist_rs->search_related('cds_unordered',
  { "me.rank" => 13 },
  {
    prefetch => 'tracks',
    join => 'genre',
    order_by => [ { -desc => 'genre.name' }, { -desc => \ 'tracks.title' }, { -asc => "me.name" }, { -desc => [qw(year cds_unordered.title)] } ], # me. is the artist, *NOT* the cd
  },
);

my $hri_contents = [
  {
    artist => 1, cdid => 1, genreid => 1, single_track => undef, title => "Spoonful of bees", year => 1999, tracks => [
      { cd => 1, last_updated_at => undef, last_updated_on => undef, position => 1, title => "The Bees Knees", trackid => 16 },
      { cd => 1, last_updated_at => undef, last_updated_on => undef, position => 3, title => "Beehind You", trackid => 18 },
      { cd => 1, last_updated_at => undef, last_updated_on => undef, position => 2, title => "Apiary", trackid => 17 },
    ],
  },
  {
    artist => 1, cdid => 3, genreid => undef, single_track => undef, title => "Caterwaulin' Blues", year => 1997, tracks => [
      { cd => 3, last_updated_at => undef, last_updated_on => undef, position => 1, title => "Yowlin", trackid => 7 },
      { cd => 3, last_updated_at => undef, last_updated_on => undef, position => 2, title => "Howlin", trackid => 8 },
      { cd => 3, last_updated_at => undef, last_updated_on => undef, position => 3, title => "Fowlin", trackid => 9 },
    ],
  },
  {
    artist => 3, cdid => 5, genreid => undef, single_track => undef, title => "Come Be Depressed With Us", year => 1998, tracks => [
      { cd => 5, last_updated_at => undef, last_updated_on => undef, position => 2, title => "Under The Weather", trackid => 14 },
      { cd => 5, last_updated_at => undef, last_updated_on => undef, position => 3, title => "Suicidal", trackid => 15 },
      { cd => 5, last_updated_at => undef, last_updated_on => undef, position => 1, title => "Sad", trackid => 13 },
    ],
  },
  {
    artist => 1, cdid => 2, genreid => undef, single_track => undef, title => "Forkful of bees", year => 2001, tracks => [
      { cd => 2, last_updated_at => undef, last_updated_on => undef, position => 1, title => "Stung with Success", trackid => 4 },
      { cd => 2, last_updated_at => undef, last_updated_on => undef, position => 2, title => "Stripy", trackid => 5 },
      { cd => 2, last_updated_at => undef, last_updated_on => undef, position => 3, title => "Sticky Honey", trackid => 6 },
    ],
  },
  {
    artist => 2, cdid => 4, genreid => undef, single_track => undef, title => "Generic Manufactured Singles", year => 2001, tracks => [
      { cd => 4, last_updated_at => undef, last_updated_on => undef, position => 3, title => "No More Ideas", trackid => 12 },
      { cd => 4, last_updated_at => undef, last_updated_on => undef, position => 2, title => "Boring Song", trackid => 11 },
      { cd => 4, last_updated_at => undef, last_updated_on => undef, position => 1, title => "Boring Name", trackid => 10},
    ],
  },
];

is_deeply(
  $filtered_cd_rs->all_hri,
  $hri_contents,
  'Expected ordered unlimited contents',
);

for (
  [ 0, 1 ],
  [ 2, 0 ],
  [ 20, 2 ],
  [ 1, 3 ],
  [ 2, 4 ],
) {
  my ($limit, $offset) = @$_;

  my $rs = $filtered_cd_rs->search({}, { $limit ? (rows => $limit) : (), offset => $offset });

  my $used_limit = $limit || $schema->storage->sql_maker->__max_int;
  my $offset_str = $offset ? 'OFFSET ?' : '';

  is_same_sql_bind(
    $rs->as_query,
    qq{(
      SELECT  "cds_unordered"."cdid", "cds_unordered"."artist", "cds_unordered"."title", "cds_unordered"."year", "cds_unordered"."genreid", "cds_unordered"."single_track",
              "tracks"."trackid", "tracks"."cd", "tracks"."position", "tracks"."title", "tracks"."last_updated_on", "tracks"."last_updated_at"
        FROM "artist" "me"
        JOIN (
          SELECT "cds_unordered"."cdid", "cds_unordered"."artist", "cds_unordered"."title", "cds_unordered"."year", "cds_unordered"."genreid", "cds_unordered"."single_track"
            FROM "artist" "me"
            JOIN cd "cds_unordered"
              ON "cds_unordered"."artist" = "me"."artistid"
            LEFT JOIN "genre" "genre"
              ON "genre"."genreid" = "cds_unordered"."genreid"
            LEFT JOIN "track" "tracks"
              ON "tracks"."cd" = "cds_unordered"."cdid"
          WHERE "me"."rank" = ?
          GROUP BY "cds_unordered"."cdid", "cds_unordered"."artist", "cds_unordered"."title", "cds_unordered"."year", "cds_unordered"."genreid", "cds_unordered"."single_track", "me"."name"
          ORDER BY  MAX("genre"."name") DESC,
                    MAX( tracks.title ) DESC,
                    "me"."name" ASC,
                    "year" DESC,
                    "cds_unordered"."title" DESC
          LIMIT ?
          $offset_str
        ) "cds_unordered"
          ON "cds_unordered"."artist" = "me"."artistid"
        LEFT JOIN "genre" "genre"
          ON "genre"."genreid" = "cds_unordered"."genreid"
        LEFT JOIN "track" "tracks"
          ON "tracks"."cd" = "cds_unordered"."cdid"
      WHERE "me"."rank" = ?
      ORDER BY  "genre"."name" DESC,
                tracks.title DESC,
                "me"."name" ASC,
                "year" DESC,
                "cds_unordered"."title" DESC
    )},
    [
      [ { sqlt_datatype => 'integer', dbic_colname => 'me.rank' } => 13 ],
      [ $ROWS => $used_limit ],
      $offset ? [ $OFFSET => $offset ] : (),
      [ { sqlt_datatype => 'integer', dbic_colname => 'me.rank' } => 13 ],
    ],
    "correct SQL on prefetch over search_related ordered by external joins with limit '$limit', offset '$offset'",
  );

  is_deeply(
    $rs->all_hri,
    [ @{$hri_contents}[$offset .. min( $used_limit+$offset-1, $#$hri_contents)] ],
    "Correct slice of the resultset returned with limit '$limit', offset '$offset'",
  );
}

done_testing;

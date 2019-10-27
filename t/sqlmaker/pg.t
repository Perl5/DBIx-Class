use strict;
use warnings;

use Test::More;

use lib 't/lib';
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema(
  no_deploy => 1,
  quote_names => 1,
  storage_type => 'DBIx::Class::Storage::DBI::Pg'
);

my $rs = $schema->resultset('Artist')->search_related('cds_unordered',
  { "me.rank" => 13 },
  {
    prefetch => 'tracks',
    join => 'genre',
    order_by => [ 'genre.name', { -desc => \ 'tracks.title' }, { -asc => "me.name" }, { -desc => [qw(year cds_unordered.title)] } ], # me. is the artist, *NOT* the cd
    rows => 1,
  },
);

{
  # THIS IS AN OFFLINE TEST
  # We only need this so that the thing can be verified to work without PG_DSN
  # Executing it while "lying" this way won't work
  local $rs->result_source->related_source('tracks')->column_info('title')->{data_type} = 'bool';
  local $rs->result_source->related_source('genre')->column_info('name')->{data_type} = 'BOOLEAN';

  is_same_sql_bind(
    $rs->as_query,
    q{(
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
          ORDER BY  BOOL_AND("genre"."name"),
                    BOOL_OR( tracks.title ) DESC,
                    "me"."name" ASC,
                    "year" DESC,
                    "cds_unordered"."title" DESC
          LIMIT ?
        ) "cds_unordered"
          ON "cds_unordered"."artist" = "me"."artistid"
        LEFT JOIN "genre" "genre"
          ON "genre"."genreid" = "cds_unordered"."genreid"
        LEFT JOIN "track" "tracks"
          ON "tracks"."cd" = "cds_unordered"."cdid"
      WHERE "me"."rank" = ?
      ORDER BY  "genre"."name",
                tracks.title DESC,
                "me"."name" ASC,
                "year" DESC,
                "cds_unordered"."title" DESC
    )},
    [
      [ { sqlt_datatype => 'integer', dbic_colname => 'me.rank' } => 13 ],
      [ DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype => 1 ],
      [ { sqlt_datatype => 'integer', dbic_colname => 'me.rank' } => 13 ],
    ],
    'correct SQL with aggregate boolean order on Pg',
  );
}

done_testing;

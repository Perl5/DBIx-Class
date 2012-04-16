use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;
use DBIx::Class::SQLMaker::LimitDialects;

my ($ROWS, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

my $schema = DBICTest->init_schema();

my $artist_rs = $schema->resultset('Artist');
my $ar = $artist_rs->current_source_alias;

my $filtered_cd_rs = $artist_rs->search_related('cds_unordered',
  { "$ar.rank" => 13 },
  {
    prefetch => [ 'tracks' ],
    order_by => [ { -asc => "$ar.name" }, "$ar.artistid DESC" ],
    offset   => 3,
    rows     => 3,
  },
);

is_same_sql_bind(
  $filtered_cd_rs->as_query,
  q{(
    SELECT  cds_unordered.cdid, cds_unordered.artist, cds_unordered.title, cds_unordered.year, cds_unordered.genreid, cds_unordered.single_track,
            tracks.trackid, tracks.cd, tracks.position, tracks.title, tracks.last_updated_on, tracks.last_updated_at
      FROM artist me
      JOIN (
        SELECT cds_unordered.cdid, cds_unordered.artist, cds_unordered.title, cds_unordered.year, cds_unordered.genreid, cds_unordered.single_track
          FROM artist me
          JOIN cd cds_unordered
            ON cds_unordered.artist = me.artistid
        WHERE ( me.rank = ? )
        ORDER BY me.name ASC, me.artistid DESC
        LIMIT ?
        OFFSET ?
      ) cds_unordered
        ON cds_unordered.artist = me.artistid
      LEFT JOIN track tracks
        ON tracks.cd = cds_unordered.cdid
    WHERE ( me.rank = ? )
    ORDER BY me.name ASC, me.artistid DESC, tracks.cd
  )},
  [
    [ { sqlt_datatype => 'integer', dbic_colname => 'me.rank' } => 13 ],
    [ $ROWS => 3 ],
    [ $OFFSET => 3 ],
    [ { sqlt_datatype => 'integer', dbic_colname => 'me.rank' } => 13 ],
  ],
  'correct SQL on limited prefetch over search_related ordered by root',
);

# note: we only requested "get all cds of all artists with rank 13 then order
# by the artist name and give me the fourth, fifth and sixth", consequently the
# cds that belong to the same artist are unordered; fortunately we know that
# the first artist have 3 cds and the second and third artist both have only
# one, so the first 3 cds belong to the first artist and the fourth and fifth
# cds belong to the second and third artist, respectively, and there's no sixth
# row
is_deeply (
  [ $filtered_cd_rs->hri_dump ],
  [
    {
      'artist' => '2',
      'cdid' => '4',
      'genreid' => undef,
      'single_track' => undef,
      'title' => 'Generic Manufactured Singles',
      'tracks' => [
        {
          'cd' => '4',
          'last_updated_at' => undef,
          'last_updated_on' => undef,
          'position' => '1',
          'title' => 'Boring Name',
          'trackid' => '10'
        },
        {
          'cd' => '4',
          'last_updated_at' => undef,
          'last_updated_on' => undef,
          'position' => '2',
          'title' => 'Boring Song',
          'trackid' => '11'
        },
        {
          'cd' => '4',
          'last_updated_at' => undef,
          'last_updated_on' => undef,
          'position' => '3',
          'title' => 'No More Ideas',
          'trackid' => '12'
        }
      ],
      'year' => '2001'
    },
    {
      'artist' => '3',
      'cdid' => '5',
      'genreid' => undef,
      'single_track' => undef,
      'title' => 'Come Be Depressed With Us',
      'tracks' => [
        {
          'cd' => '5',
          'last_updated_at' => undef,
          'last_updated_on' => undef,
          'position' => '1',
          'title' => 'Sad',
          'trackid' => '13'
        },
        {
          'cd' => '5',
          'last_updated_at' => undef,
          'last_updated_on' => undef,
          'position' => '3',
          'title' => 'Suicidal',
          'trackid' => '15'
        },
        {
          'cd' => '5',
          'last_updated_at' => undef,
          'last_updated_on' => undef,
          'position' => '2',
          'title' => 'Under The Weather',
          'trackid' => '14'
        }
      ],
      'year' => '1998'
    }
  ],
  'Correctly ordered result',
);

done_testing;

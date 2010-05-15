use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();
$schema->storage->sql_maker->quote_char ('"');
$schema->storage->sql_maker->name_sep ('.');

my $rs = $schema->resultset('CD')->search({}, {
    'join' => 'tracks',
    order_by => [
      { -length => 'me.title' },
      {
        -desc => {
            count => 'tracks.trackid',
        },
      },
    ],
    distinct => 1,
    rows => 2,
    page => 2,
});

is_same_sql_bind(
  $rs->as_query,
  '(
    SELECT "me"."cdid", "me"."artist", "me"."title", "me"."year", "me"."genreid", "me"."single_track"
      FROM cd "me"
      LEFT JOIN "track" "tracks" ON "tracks"."cd" = "me"."cdid"
    GROUP BY "me"."cdid", "me"."artist", "me"."title", "me"."year", "me"."genreid", "me"."single_track"
    ORDER BY
      LENGTH( "me"."title" ),
      COUNT( "tracks"."trackid" ) DESC
    LIMIT 2 OFFSET 2
  )',
  [],
  'order by with func query',
);

ok($rs->count_rs->next == 2, 'amount of rows return in order by func query');
is_deeply (
  [ $rs->get_column ('me.title')->all ],
  [ "Caterwaulin' Blues", "Come Be Depressed With Us" ],
  'Correctly ordered stuff by title-length',
);

done_testing;

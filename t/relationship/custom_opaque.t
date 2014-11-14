use strict;
use warnings;

use Test::More;

use lib 't/lib';
use DBICTest;

my $schema = DBICTest->init_schema( no_populate => 1, quote_names => 1 );

$schema->resultset('CD')->create({
  title => 'Equinoxe',
  year => 1978,
  artist => { name => 'JMJ' },
  genre => { name => 'electro' },
  tracks => [
    { title => 'e1' },
    { title => 'e2' },
    { title => 'e3' },
  ],
  single_track => {
    title => 'o1',
    cd => {
      title => 'Oxygene',
      year => 1976,
      artist => { name => 'JMJ' },
    },
  },
});

my $cd = $schema->resultset('CD')->search({ single_track => { '!=', undef } })->first;

$schema->is_executed_sql_bind(
  sub { is( eval{$cd->single_track_opaque->title}, 'o1', 'Found correct single track' ) },
  [
    [
      'SELECT "me"."trackid", "me"."cd", "me"."position", "me"."title", "me"."last_updated_on", "me"."last_updated_at"
          FROM cd "cd__row"
          JOIN "track" "me"
            ON me.trackid = cd__row.single_track
        WHERE "cd__row"."cdid" = ?
      ',
      [
        { dbic_colname => "cd__row.cdid", sqlt_datatype => "integer" }
          => 2
      ]
    ],
  ],
);

done_testing;

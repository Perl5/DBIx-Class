use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

my $ne_bind = [ _ne => 'bar' ];
my $rs = $schema->resultset('CD')->search({ -and => [
  'me.artist' => { '!=', 'foo' },
  'me.artist' => { '!=', \[ '?', $ne_bind ] },
]});

# bogus sql query to make sure bind composition happens properly
my $complex_rs = $rs->search({}, {
  '+columns' => { cnt => $rs->count_rs->as_query },
  '+select' => \[ 'me.artist + ?', [ _add => 1 ] ], # free select
  group_by => ['me.cdid', \[ 'me.artist - ?', [ _sub => 2 ] ] ],
  having => \[ 'me.artist < ?', [ _lt => 3 ] ],
  order_by => \[ 'me.artist * ? ', [ _mu => 4 ] ],
  rows => 1,
  page => 3,
});

for (1,2) {
  is_same_sql_bind (
    $complex_rs->as_query,
    '(
      SELECT  me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track,
              (SELECT COUNT( * ) FROM cd me WHERE me.artist != ? AND me.artist != ?),
              me.artist + ?
        FROM cd me
      WHERE me.artist != ? AND me.artist != ?
      GROUP BY me.cdid, me.artist - ?
      HAVING me.artist < ?
      ORDER BY me.artist * ?
      LIMIT 1 OFFSET 2
    )',
    [
      [ 'me.artist' => 'foo' ],
      $ne_bind,
      [ _add => 1 ],
      [ 'me.artist' => 'foo' ],
      $ne_bind,
      [ _sub => 2 ],
      [ _lt => 3 ],
      [ _mu => 4 ],
    ],
    'Correct crazy sql',
  );
}

# see if we get anything back at all
isa_ok ($complex_rs->next, 'DBIx::Class::Row');

done_testing;

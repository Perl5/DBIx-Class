use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;

my ($ROWS, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__rows_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset('CD')->search({ -and => [
  'me.artist' => { '!=', '666' },
  'me.artist' => { '!=', \[ '?', [ _ne => 'bar' ] ] },
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
      LIMIT ? OFFSET ?
    )',
    [
      [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' } => 666 ],
      [ { dbic_colname => '_ne' } => 'bar' ],
      [ { dbic_colname => '_add' } => 1 ],
      [ { sqlt_datatype => 'integer', dbic_colname => 'me.artist' } => 666 ],
      [ { dbic_colname => '_ne' } => 'bar' ],
      [ { dbic_colname => '_sub' } => 2 ],
      [ { dbic_colname => '_lt' } => 3 ],
      [ { dbic_colname => '_mu' } => 4 ],
      [ $ROWS => 1 ],
      [ $OFFSET => 2 ],
    ],
    'Correct crazy sql',
  );
}

# see if we get anything back at all
isa_ok ($complex_rs->next, 'DBIx::Class::Row');

done_testing;

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Math::BigInt;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my ($ROWS, $OFFSET) = (
   DBIx::Class::SQLMaker::ClassicExtensions->__rows_bindtype,
   DBIx::Class::SQLMaker::ClassicExtensions->__offset_bindtype,
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

# Make sure that the bind shorthand syntax translation is accurate (and doesn't error)
shorthand_check(
  [ _sub => 2 ],
  [ { dbic_colname => '_sub' } => 2 ],
  '[ $name => $val ] === [ { dbic_colname => $name }, $val ]',
);
shorthand_check(
  [ artist => 2 ],
  [ { dbic_colname => 'artist', sqlt_datatype => 'integer' } => 2 ],
  'resolution of known column during [ $name => $val ] === [ { dbic_colname => $name }, $val ]',
);
shorthand_check(
  [ \ 'number' => 2 ],
  [ { sqlt_datatype => 'number' } => 2 ],
  '[ \$dt => $val ] === [ { sqlt_datatype => $dt }, $val ]',
);
shorthand_check(
  [ {} => 2 ],
  [ {} => 2 ],
  '[ {} => $val ] === [ {}, $val ]',
);
shorthand_check(
  [ undef, 2 ],
  [ {} => 2 ],
  '[ undef, $val ] === [ {}, $val ]',
);
shorthand_check(
  2,
  [ {} => 2 ],
  '$val === [ {}, $val ]',
);

shorthand_check(
  Math::BigInt->new(42),
  [ {} => Math::BigInt->new(42) ],
  'stringifyable $object === [ {}, $object ]',
);

shorthand_check(
    [ 2 ],
    [ {} => [ 2 ] ],
);

shorthand_check(
    [ {} => [ 2 ] ],
    [ {} => [ 2 ] ],
);

shorthand_check(
    [ {}, 2, 3 ],
    [ {} => [ {}, 2, 3 ] ],
);

shorthand_check(
    bless( {}, 'Foo'),
    [ {} => bless( {}, 'Foo') ],
);

shorthand_check(
    [ {}, bless( {}, 'Foo') ],
    [ {}, bless( {}, 'Foo') ],
);


sub shorthand_check {
  my ($bind_shorthand, $bind_expected, $testname) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  is_same_sql_bind (
    $schema->resultset('CD')->search({}, {
      columns => [qw(cdid artist)],
      group_by => ['cdid', \[ 'artist - ?', $bind_shorthand ] ],
    })->as_query,
    '(
      SELECT me.cdid, me.artist
        FROM cd me
      GROUP BY cdid, artist - ?
    )',
    [ $bind_expected ],
    $testname||(),
  );
}

undef $schema;

done_testing;

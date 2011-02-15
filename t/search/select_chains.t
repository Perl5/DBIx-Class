use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;


my $schema = DBICTest->init_schema();

my @chain = (
  {
    columns     => [ 'cdid' ],
    '+columns'  => [ { title_lc => { lower => 'title', -as => 'lctitle' } } ],
    '+select'   => [ 'genreid' ],
    '+as'       => [ 'genreid' ],
  } => 'SELECT me.cdid, LOWER( title ) AS lctitle, me.genreid FROM cd me',

  {
    '+columns'  => [ { max_year => { max => 'me.year', -as => 'last_y' }}, ],
    '+select'   => [ { count => 'me.cdid' }, ],
    '+as'       => [ 'cnt' ],
  } => 'SELECT me.cdid, LOWER( title ) AS lctitle, MAX( me.year ) AS last_y, me.genreid, COUNT( me.cdid ) FROM cd me',

  {
    select      => [ { min => 'me.cdid' }, ],
    as          => [ 'min_id' ],
  } => 'SELECT MIN( me.cdid ) FROM cd me',

  {
    '+columns' => [ { cnt => { count => 'cdid', -as => 'cnt' } } ],
  } => 'SELECT COUNT ( cdid ) AS cnt, MIN( me.cdid ) FROM cd me',

  {
    columns => [ { foo => { coalesce => [qw/a b c/], -as => 'firstfound' } }  ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound FROM cd me',

  {
    '+columns' => [ 'me.year' ],
    '+select' => [ { max => 'me.year', -as => 'last_y' } ],
    '+as' => [ 'ly' ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y FROM cd me',

  {
    '+select'   => [ { count => 'me.cdid', -as => 'cnt' } ],
    '+as'       => [ 'cnt' ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt FROM cd me',

  # adding existing stuff should not alter selector
  {
    '+select'   => [ 'me.year' ],
    '+as'       => [ 'year' ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt, me.year FROM cd me',

  {
    '+columns'   => [ 'me.year' ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt, me.year FROM cd me',

  {
    '+columns'   => 'me.year',
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt, me.year FROM cd me',

  # naked selector at the end should just work
  {
    '+select'   => 'me.moar_stuff',
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt, me.year, me.moar_stuff FROM cd me',

  {
    '+select'   => [ { MOAR => 'f', -as => 'func' } ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt, me.year, me.moar_stuff, MOAR(f) AS func FROM cd me',

);

my $rs = $schema->resultset('CD');

my $testno = 1;
while (@chain) {
  my $attrs = shift @chain;
  my $sql = shift @chain;

  $rs = $rs->search ({}, $attrs);

  is_same_sql_bind (
    $rs->as_query,
    "($sql)",
    [],
    "Test $testno of SELECT assembly ok",
  );

  $testno++;
}

# Make sure we don't lose bits even with weird selector specs
# also check that the default selector list is lazy
# and make sure that unaliased +select does not go crazy
$rs = $schema->resultset('CD');
for my $attr (
  { '+columns'  => [ 'me.title' ] },    # this one should be de-duplicated but not the select's

  { '+select'   => \'me.year AS foo' },   # duplication of identical select expected (FIXME ?)
  { '+select'   => \['me.year AS foo'] },

  { '+select'   => [ \'me.artistid AS bar' ] },
  { '+select'   => { count => 'artistid', -as => 'baz' } },
) {
  for (qw/columns select as/) {
    ok (! exists $rs->{attrs}{$_}, "No eager '$_' attr on fresh resultset" );
  }

  $rs = $rs->search({}, $attr);
}

is_same_sql_bind (
  $rs->as_query,
  '( SELECT
      me.cdid,
      me.artist,
      me.title,
      me.year,
      me.genreid,
      me.single_track,
      me.year AS foo,
      me.year AS foo,
      me.artistid AS bar,
      COUNT( artistid ) AS baz
        FROM cd me
  )',
  [],
  'Correct chaining before attr resolution'
);

# Test the order of columns
$rs = $schema->resultset('CD')->search ({}, {
  'select'   => [ 'me.cdid', 'me.title' ],
});

is_same_sql_bind (
  $rs->as_query,
  '( SELECT
      me.cdid,
      me.title
      FROM cd me
  )',
  [],
  'Correct order of selected columns'
);

# Test bare +select with as from root of resultset
$rs = $schema->resultset('CD')->search ({}, {
  '+select'   => [
    \ 'foo',
    { MOAR => 'f', -as => 'func' },
   ],
});

is_same_sql_bind (
  $rs->as_query,
  '( SELECT
      me.cdid,
      me.artist,
      me.title,
      me.year,
      me.genreid,
      me.single_track,
      foo,
      MOAR( f ) AS func
       FROM cd me
  )',
  [],
  'Correct order of selected columns'
);

done_testing;

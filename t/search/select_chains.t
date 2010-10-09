use strict;
use warnings;

use Test::More;
use Test::Exception;

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
  } => 'SELECT MIN( me.cdid ), COUNT ( cdid ) AS cnt FROM cd me',

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
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt FROM cd me',

  {
    '+columns'   => [ 'me.year' ],
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt FROM cd me',

  {
    '+columns'   => 'me.year',
  } => 'SELECT COALESCE( a, b, c ) AS firstfound, me.year, MAX( me.year ) AS last_y, COUNT( me.cdid ) AS cnt FROM cd me',

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
$rs = $schema->resultset('CD')->search ({}, {
  'columns'   => [ 'me.title' ],
})->search ({}, {
  '+select'   => \'me.year AS foo',
})->search ({}, {
  '+select'   => [ \'me.artistid AS bar' ],
})->search ({}, {
  '+select'   => { count => 'artistid', -as => 'baz' },
});

is_same_sql_bind (
  $rs->as_query,
  '( SELECT
      me.title,
      me.year AS foo,
      me.artistid AS bar,
      COUNT( artistid ) AS baz
        FROM cd me
  )',
  [],
  'Correct chaining before attr resolution'
);

done_testing;

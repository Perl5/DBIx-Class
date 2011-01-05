use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;


my $schema = DBICTest->init_schema();

my $multicol_rs = $schema->resultset('Artist')->search({ artistid => \'1' }, { columns => [qw/name rank/] });

my @chain = (
  {
    select      => 'title',
    as          => 'title',
    columns     => [ 'cdid' ],
  } => 'SELECT
          me.cdid,
          me.title
        FROM cd me'
    => [qw/cdid title/],

  {
    '+select'   => \ 'DISTINCT(foo, bar)',
    '+as'       => [qw/foo bar/],
  } => 'SELECT
          me.cdid,
          me.title,
          DISTINCT(foo, bar)
        FROM cd me'
    => [qw/cdid title foo bar/],

  {
    '+select'   => \'unaliased randomness',
  } => 'SELECT
          me.cdid,
          me.title,
          DISTINCT(foo, bar),
          unaliased randomness
        FROM cd me'
    => [qw/cdid title foo bar/],
  {
    '+select'   => [ 'genreid', $multicol_rs->as_query ],
    '+as'       => [qw/genreid name rank/],
  } => 'SELECT
          me.cdid,
          me.title,
          DISTINCT(foo, bar),
          me.genreid,
          (SELECT me.name, me.rank FROM artist me WHERE ( artistid 1 )),
          unaliased randomness
        FROM cd me'
    => [qw/cdid title foo bar genreid name rank/],

  {
    '+select'   => { count => 'me.cdid', -as => 'cnt' },  # lack of 'as' infers from '-as'
    '+columns'  => { len => { length => 'me.title' } },
  } => 'SELECT
          me.cdid,
          me.title,
          LENGTH( me.title ),
          COUNT( me.cdid ) AS cnt,
          DISTINCT(foo, bar),
          me.genreid,
          (SELECT me.name, me.rank FROM artist me WHERE ( artistid 1 )),
          unaliased randomness
        FROM cd me'
    => [qw/cdid title len cnt foo bar genreid name rank/],


);

my $rs = $schema->resultset('CD');

my $testno = 1;
while (@chain) {
  my $attrs = shift @chain;
  my $sql = shift @chain;
  my $as = shift @chain;

  $rs = $rs->search ({}, $attrs);

  is_same_sql_bind (
    $rs->as_query,
    "($sql)",
    [],
    "Test $testno of SELECT assembly ok",
  );

  is_deeply(
    $rs->_resolved_attrs->{as},
    $as,
    "Correct dbic-side aliasing for test $testno",
  );

  $testno++;
}

done_testing;

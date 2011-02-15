use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;


my $schema = DBICTest->init_schema();

my $multicol_rs = $schema->resultset('Artist')->search({ artistid => \'1' }, { columns => [qw/name rank/] });

my @chain = (
  {
    select      => 'cdid',
    as          => 'cd_id',
    columns     => [ 'title' ],
  } => 'SELECT
          me.title,
          me.cdid
        FROM cd me'
    => [qw/title cd_id/],

  {
    '+select'   => \ 'DISTINCT(foo, bar)',
    '+as'       => [qw/foo bar/],
  } => 'SELECT
          me.title,
          me.cdid,
          DISTINCT(foo, bar)
        FROM cd me'
    => [qw/title cd_id foo bar/],

  {
    '+select'   => [ 'genreid', $multicol_rs->as_query ],
    '+as'       => [qw/genreid name rank/],
  } => 'SELECT
          me.title,
          me.cdid,
          DISTINCT(foo, bar),
          me.genreid,
          (SELECT me.name, me.rank FROM artist me WHERE ( artistid 1 )),
        FROM cd me'
    => [qw/title cd_id foo bar genreid name rank/],

  {
    '+select'   => { count => 'me.cdid', -as => 'cnt' },  # lack of 'as' infers from '-as'
    '+columns'  => { len => { length => 'me.title' } },
  } => 'SELECT
          me.title,
          LENGTH( me.title ),
          me.cdid,
          DISTINCT(foo, bar),
          me.genreid,
          (SELECT me.name, me.rank FROM artist me WHERE ( artistid 1 )),
          COUNT( me.cdid ) AS cnt,
        FROM cd me'
    => [qw/title len cd_id foo bar genreid name rank cnt/],
  {
    '+select'   => \'unaliased randomness',
  } => 'SELECT
          me.title,
          LENGTH( me.title ),
          me.cdid,
          DISTINCT(foo, bar),
          me.genreid,
          (SELECT me.name, me.rank FROM artist me WHERE ( artistid 1 )),
          COUNT( me.cdid ) AS cnt,
          unaliased randomness
        FROM cd me'
    => [qw/title len cd_id foo bar genreid name rank cnt/],
  {
    '+select'   => \'MOAR unaliased randomness',
  } => 'SELECT
          me.title,
          LENGTH( me.title ),
          me.cdid,
          DISTINCT(foo, bar),
          me.genreid,
          (SELECT me.name, me.rank FROM artist me WHERE ( artistid 1 )),
          COUNT( me.cdid ) AS cnt,
          unaliased randomness,
          MOAR unaliased randomness
        FROM cd me'
    => [qw/title len cd_id foo bar genreid name rank cnt/],
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

# make sure proper exceptions are thrown on unbalanced use
{
  my $rs = $schema->resultset('CD')->search({}, { select => \'count(me.cdid)'});

  lives_ok(sub {
    $rs->search({}, { '+select' => 'me.cdid' })->next
  }, 'Two dark selectors are ok');

  throws_ok(sub {
    $rs->search({}, { '+select' => 'me.cdid', '+as' => 'cdid' })->next
  }, qr/resultset contains an unnamed selector/, 'Unnamed followed by named is not');

  throws_ok(sub {
    $rs->search_rs({}, { prefetch => 'tracks' })->next
  }, qr/resultset contains an unnamed selector/, 'Throw on unaliased selector followed by prefetch');

  throws_ok(sub {
    $rs->search_rs({}, { '+select' => 'me.title', '+as' => 'title'  })->next
  }, qr/resultset contains an unnamed selector/, 'Throw on unaliased selector followed by +select/+as');
}


done_testing;

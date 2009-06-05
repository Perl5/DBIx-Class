use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema;

# Trick the sqlite DB to use Top limit emulation
# We could test all of this via $sq->$op directly,
# but some conditions needs a $rsrc
delete $schema->storage->_sql_maker->{_cached_syntax};
$schema->storage->_sql_maker->limit_dialect ('Top');

my $rs = $schema->resultset ('FourKeys')->search ({}, { rows => 1, offset => 3 });

sub test_order {
  my $args = shift;

  my $req_order = $args->{order_req}
    ? "ORDER BY $args->{order_req}"
    : ''
  ;

  is_same_sql_bind(
    $rs->search ({}, {order_by => $args->{order_by}})->as_query,
    "(
      SELECT * FROM (
        SELECT TOP 1 * FROM (
          SELECT TOP 4 me.foo, me.bar, me.hello, me.goodbye, me.sensors, me.read_count FROM fourkeys me ORDER BY $args->{order_inner}
        ) foo ORDER BY $args->{order_outer}
      ) bar
      $req_order
    )",
    [],
  );
}

my @tests = (
  {
    order_by => \ 'foo DESC',
    order_req => 'foo DESC',
    order_inner => 'foo DESC',
    order_outer => 'foo ASC' 
  },
  {
    order_by => { -asc => 'foo'  },
    order_req => 'foo ASC',
    order_inner => 'foo ASC',
    order_outer => 'foo DESC',
  },
  {
    order_by => 'foo',
    order_req => 'foo',
    order_inner => 'foo ASC',
    order_outer => 'foo DESC',
  },
  {
    order_by => [ qw{ foo bar}   ],
    order_req => 'foo, bar',
    order_inner => 'foo ASC,bar ASC',
    order_outer => 'foo DESC, bar DESC',
  },
  {
    order_by => { -desc => 'foo' },
    order_req => 'foo DESC',
    order_inner => 'foo DESC',
    order_outer => 'foo ASC',
  },
  {
    order_by => ['foo', { -desc => 'bar' } ],
    order_req => 'foo, bar DESC',
    order_inner => 'foo ASC, bar DESC',
    order_outer => 'foo DESC, bar ASC',
  },
  {
    order_by => { -asc => [qw{ foo bar }] },
    order_req => 'foo ASC, bar ASC',
    order_inner => 'foo ASC, bar ASC',
    order_outer => 'foo DESC, bar DESC',
  },
  {
    order_by => [
      { -asc => 'foo' },
      { -desc => [qw{bar}] },
      { -asc  => [qw{hello sensors}]},
    ],
    order_req => 'foo ASC, bar DESC, hello ASC, sensors ASC',
    order_inner => 'foo ASC, bar DESC, hello ASC, sensors ASC',
    order_outer => 'foo DESC, bar ASC, hello DESC, sensors DESC',
  },
  {
    order_by => undef,
    order_req => undef,
    order_inner => 'foo ASC, bar ASC, hello ASC, goodbye ASC',
    order_outer => 'foo DESC, bar DESC, hello DESC, goodbye DESC',
  },
  {
    order_by => '',
    order_req => undef,
    order_inner => 'foo ASC, bar ASC, hello ASC, goodbye ASC',
    order_outer => 'foo DESC, bar DESC, hello DESC, goodbye DESC',
  },
  {
    order_by => {},
    order_req => undef,
    order_inner => 'foo ASC, bar ASC, hello ASC, goodbye ASC',
    order_outer => 'foo DESC, bar DESC, hello DESC, goodbye DESC',
  },
  {
    order_by => [],
    order_req => undef,
    order_inner => 'foo ASC, bar ASC, hello ASC, goodbye ASC',
    order_outer => 'foo DESC, bar DESC, hello DESC, goodbye DESC',
  },
);

plan (tests => scalar @tests + 1);

test_order ($_) for @tests;

is_same_sql_bind (
  $rs->search ({}, { group_by => 'bar', order_by => 'bar' })->as_query,
  '(
    SELECT * FROM
    (
      SELECT TOP 1 * FROM
      (
        SELECT TOP 4  me.foo, me.bar, me.hello, me.goodbye, me.sensors, me.read_count FROM fourkeys me GROUP BY bar ORDER BY bar ASC
      ) AS foo
      ORDER BY bar DESC
    ) AS bar
    ORDER BY bar
  )',
  [],
);

use strict;
use warnings;

use Test::More;
use DBIx::Class::Storage::DBI;
use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used
use DBIC::SqlMakerTest;

plan tests => 8;

my $sa = new DBIx::Class::SQLAHacks;
$sa->limit_dialect( 'Top' );

sub test_order {
  my $args = shift;
  my $order_by = $args->{order_by};
  my $expected_sql_order = $args->{expected_sql_order};

  my $query = $sa->select( 'foo', [qw{bar baz}], undef, {
      order_by => $order_by,
     }, 1, 3
  );
  is_same_sql(
    $query,
    "SELECT * FROM ( SELECT TOP 1 * FROM ( SELECT TOP 4 bar,baz FROM foo ORDER BY $expected_sql_order->[0] ) AS foo ORDER BY $expected_sql_order->[1] ) AS bar ORDER BY $expected_sql_order->[0]",
  );
}

  test_order({ order_by => \'foo DESC'       , expected_sql_order => [ 'foo DESC', 'foo ASC' ] });
  test_order({ order_by => 'foo'             , expected_sql_order => [ 'foo ASC', 'foo DESC'] });
  test_order({ order_by => [ qw{ foo bar}   ], expected_sql_order => [ 'foo ASC,bar ASC', 'foo DESC, bar DESC']});
  test_order({ order_by => { -asc => 'foo'  }, expected_sql_order => [ 'foo ASC', 'foo DESC' ] });
  test_order({ order_by => { -desc => 'foo' }, expected_sql_order => [ 'foo DESC', 'foo ASC' ] });

  test_order({ order_by => ['foo', { -desc => 'bar' } ], expected_sql_order => [ 'foo ASC, bar DESC', 'foo DESC, bar ASC'] });
  test_order({ order_by => {-asc => [qw{ foo bar }] }, expected_sql_order => ['foo ASC, bar ASC', 'foo DESC, bar DESC' ] });
  test_order({ order_by =>
      [
        { -asc => 'foo' },
        { -desc => [qw{bar}] },
        { -asc  => [qw{baz frew}]},
      ],
      expected_sql_order => ['foo ASC, bar DESC, baz ASC, frew ASC', 'foo DESC, bar ASC, baz DESC, frew DESC']
  });

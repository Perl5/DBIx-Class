use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;

my $schema = DBICTest->init_schema();

# make sure order + distinct do not double-inject group criteria
my $year_rs = $schema->resultset ('CD')->search ({}, {
  distinct => 1,
  columns => [qw/year/],
  order_by => 'year',
});

is_same_sql_bind (
  $year_rs->as_query,
  '(
    SELECT me.year
      FROM cd me
    GROUP BY me.year
    ORDER BY year
  )',
  [],
  'Correct GROUP BY',
);

done_testing;

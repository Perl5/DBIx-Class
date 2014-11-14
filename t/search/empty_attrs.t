use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset('Artist')->search(
  [ -and => [ {}, [] ], -or => [ {}, [] ] ],
  {
    select => [],
    columns => {},
    '+columns' => 'artistid',
    join => [ {}, [ [ {}, {} ] ], {} ],
    prefetch => [ [ [ {}, [] ], {} ], {}, [ {} ] ],
    order_by => [],
    group_by => [],
    offset => 0,
  }
);

is_same_sql_bind(
  $rs->as_query,
  '(SELECT me.artistid FROM artist me)',
  [],
);

is_same_sql_bind(
  $rs->count_rs->as_query,
  '(SELECT COUNT(*) FROM artist me)',
  [],
);

is_same_sql_bind(
  $rs->as_subselect_rs->search({}, { columns => 'artistid' })->as_query,
  '(SELECT me.artistid FROM (SELECT me.artistid FROM artist me) me)',
  [],
);

{
  local $TODO = 'Stupid misdesigned as_subselect_rs';
  is_same_sql_bind(
    $rs->as_subselect_rs->as_query,
    $rs->as_subselect_rs->search({}, { columns => 'artistid' })->as_query,
  );
}

done_testing;

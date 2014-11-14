use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd = $schema->resultset('CD')->search({}, {
  '+columns' => { avg_year => $schema->resultset('CD')->get_column('year')->func_rs('avg')->as_query },
  order_by => 'cdid',
})->next;

my $ccd = $cd->copy({ cdid => 5_000_000, artist => 2 });

cmp_ok(
  $ccd->id,
  '!=',
  $cd->id,
  'IDs differ'
);

is(
  $ccd->title,
  $cd->title,
  'Title same on copied object',
);

done_testing;

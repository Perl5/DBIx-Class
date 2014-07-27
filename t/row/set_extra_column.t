use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $rs_with_avg = $schema->resultset('CD')->search({}, {
  '+columns' => { avg_year => $schema->resultset('CD')->get_column('year')->func_rs('avg')->as_query },
  order_by => 'cdid',
});

for my $in_storage (1, 0) {
  my $cd = $rs_with_avg->first;

  ok ! $cd->is_column_changed('avg_year'), 'no changes';

  $cd->in_storage($in_storage);

  ok ! $cd->is_column_changed('avg_year'), 'still no changes';

  $cd->set_column( avg_year => 42 );
  $cd->set_column( avg_year => 69 );

  ok $cd->is_column_changed('avg_year'), 'changed';
  is $cd->get_column('avg_year'), 69, 'correct value'
}

done_testing;

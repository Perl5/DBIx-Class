use strict;
use warnings;

use Test::More;

use lib qw(t/lib);

use DBICTest;

my $schema = DBICTest->init_schema();
my $cd_rs = $schema->resultset('CD')->search ({}, { rows => 1, order_by => 'cdid' });

my $track_count = $cd_rs->first->tracks->count;

cmp_ok ($track_count, '>', 1, 'First CD has several tracks');

is ($cd_rs->search_related ('tracks')->count, $track_count, 'related->count returns correct number');
is (scalar ($cd_rs->search_related ('tracks')->all), $track_count, 'related->all returns correct number of objects');

done_testing;

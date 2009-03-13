use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use lib '/sporkrw/xfer/DBIx-Class/0.08/branches/count_distinct/lib';
use DBICTest;

my $schema = DBICTest->init_schema();

eval "use DBD::SQLite";
plan skip_all => 'needs DBD::SQLite for testing' if $@;
plan tests => 4;

cmp_ok($schema->resultset("Tag")->count({ tag => 'Blue' }),
           '==', 9, 'Count without DISTINCT ok');

cmp_ok($schema->resultset("Tag")->count({ tag => [ 'Blue', 'Shiny' ] }, { group_by => 'tag' }),
           '==', 2, 'Count with single column group_by ok');

cmp_ok($schema->resultset("Tag")->count({ tag => 'Blue' }, { group_by => [ qw/tag cd/ ]}), 
           '==', 4, 'Count with multiple column group_by ok');

cmp_ok($schema->resultset("Tag")->count({ tag => 'Blue' }, { distinct => 1 }),
           '==', 4, "Count with single column distinct ok");


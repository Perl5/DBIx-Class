use strict;
use warnings;  

use Test::More;

use lib qw(t/lib);

use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

eval "use DBD::SQLite";
plan skip_all => 'needs DBD::SQLite for testing' if $@;
plan tests => 13;

my $in_rs = $schema->resultset("Tag")->search({ tag => [ 'Blue', 'Shiny' ] });

cmp_ok($schema->resultset("Tag")->count({ tag => 'Blue' }),
           '==', 4, 'Count without DISTINCT');

cmp_ok($schema->resultset("Tag")->count({ tag => [ 'Blue', 'Shiny' ] }, { group_by => 'tag' }),
           '==', 2, 'Count with single column group_by');

cmp_ok($schema->resultset("Tag")->count({ tag => 'Blue' }, { group_by => [ qw/tag cd/ ]}), 
           '==', 4, 'Count with multiple column group_by');

cmp_ok($schema->resultset("Tag")->count({ tag => 'Blue' }, { distinct => 1 }),
           '==', 4, "Count with single column distinct");

cmp_ok($schema->resultset("Tag")->count({ tag => { -in => $in_rs->get_column('tag')->as_query } }),
           '==', 4, "Count with IN subquery");

cmp_ok($schema->resultset("Tag")->count({ tag => { -in => $in_rs->get_column('tag')->as_query } }, { group_by => 'tag' }),
           '==', 1, "Count with IN subquery with outside group_by");

cmp_ok($schema->resultset("Tag")->count({ tag => { -in => $in_rs->get_column('tag')->as_query } }, { distinct => 1 }),
           '==', 4, "Count with IN subquery with outside distinct");

cmp_ok($schema->resultset("Tag")->count({ tag => { -in => $in_rs->get_column('tag')->as_query } }, { distinct => 1, select => 'tag' }),
           '==', 1, "Count with IN subquery with outside distinct on a single column");

cmp_ok($schema->resultset("Tag")->count({ tag => { -in => $in_rs->search({}, { group_by => 'tag' })->get_column('tag')->as_query } }),
           '==', 4, "Count with IN subquery with single group_by");

cmp_ok($schema->resultset("Tag")->count({ tag => { -in => $in_rs->search({}, { group_by => [ qw/tag cd/ ] })->get_column('tag')->as_query } }),
           '==', 4, "Count with IN subquery with multiple group_by");

cmp_ok($schema->resultset("Tag")->count({ tag => \"= 'Blue'" }),
           '==', 4, "Count without DISTINCT, using literal SQL");

cmp_ok($schema->resultset("Tag")->count({ tag => \" IN ('Blue', 'Shiny')" }, { group_by => 'tag' }),
           '==', 2, "Count with literal SQL and single group_by");

cmp_ok($schema->resultset("Tag")->count({ tag => \" IN ('Blue', 'Shiny')" }, { group_by => [ qw/tag cd/ ] }),
           '==', 6, "Count with literal SQL and multiple group_by");

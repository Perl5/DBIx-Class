use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest::init_schema();

plan tests => 5; 

my $rs = $cd = $schema->resultset("CD")->search({});

my $rs_title = $rs->get_column('title');
my $rs_year = $rs->get_column('year');

is($rs_title->next, 'Spoonful of bees', "next okay");

my @all = $rs_title->all;
cmp_ok(scalar @all, '==', 5, "five titles returned");

cmp_ok($rs_year->max, '==', 2001, "max okay for year");
is($rs_title->min, 'Caterwaulin\' Blues', "min okay for title");

cmp_ok($rs_year->sum, '==', 9996, "three artists returned");


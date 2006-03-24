use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

require "t/run/27adjacency_list.tl";
run_tests(DBICTest->schema);

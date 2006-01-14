use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

require "t/run/13oracle.tl";
run_tests("DBICTest");

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/08inflate.tl";
run_tests("DBICTest");

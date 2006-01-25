use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/15limit.tl";
run_tests(DBICTest->schema);

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/22cache.tl";
run_tests(DBICTest->schema);

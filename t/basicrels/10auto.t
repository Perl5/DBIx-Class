use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/10auto.tl";
run_tests(DBICTest->schema);

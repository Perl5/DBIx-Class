use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/27ordered.tl";
run_tests(DBICTest->schema);

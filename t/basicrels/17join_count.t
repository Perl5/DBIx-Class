use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/17join_count.tl";
run_tests(DBICTest->schema);

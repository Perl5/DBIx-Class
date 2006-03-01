use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::BasicRels;

require "t/run/24serialize.tl";
run_tests(DBICTest->schema);

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

require "t/run/08inflate_has_a.tl";
run_tests(DBICTest->schema);

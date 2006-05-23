use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

require "t/run/30ensure_class_loaded.tl";
run_tests(DBICTest->schema);

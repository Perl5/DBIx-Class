use Test::More;

plan tests => 3;

use lib qw(t/lib);

use_ok('DBICTest');

ok(DBICTest::FourKeys->retrieve(1,2,3,4), "retrieve multiple pks without hash");
ok(DBICTest::FourKeys->retrieve(5,4,3,6), "retrieve multiple pks without hash");
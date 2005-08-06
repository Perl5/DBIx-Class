use Test::More;

plan tests => 3;

use lib qw(t/lib);

use_ok('DBICTest');

ok(DBICTest::FourKeys->find(1,2,3,4), "find multiple pks without hash");
ok(DBICTest::FourKeys->find(5,4,3,6), "find multiple pks without hash");

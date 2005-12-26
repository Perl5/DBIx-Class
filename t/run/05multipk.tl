sub run_tests {

plan tests => 3;

ok(DBICTest->class("FourKeys")->find(1,2,3,4), "find multiple pks without hash");
ok(DBICTest->class("FourKeys")->find(5,4,3,6), "find multiple pks without hash");

is(DBICTest->class("FourKeys")->find(1,2,3,4)->ID, 'DBICTest::FourKeys|bar=2|foo=1|goodbye=4|hello=3', 'unique object id ok for multiple pks');

}

1;

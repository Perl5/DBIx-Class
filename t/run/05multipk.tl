sub run_tests {

plan tests => 2;

ok(DBICTest::FourKeys->find(1,2,3,4), "find multiple pks without hash");
ok(DBICTest::FourKeys->find(5,4,3,6), "find multiple pks without hash");

}

1;

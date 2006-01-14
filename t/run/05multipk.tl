sub run_tests {
my $schema = shift;

plan tests => 4;
$artist = DBICTest::Artist->find(1);
ok($artist->find_related('twokeys', {cd => 1}), "find multiple pks using relationships + args");
ok($schema->resultset("FourKeys")->find(1,2,3,4), "find multiple pks without hash");
ok($schema->resultset("FourKeys")->find(5,4,3,6), "find multiple pks without hash");
is($schema->resultset("FourKeys")->find(1,2,3,4)->ID, 'DBICTest::FourKeys|bar=2|foo=1|goodbye=4|hello=3', 'unique object id ok for multiple pks');

}

1;

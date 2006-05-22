sub run_tests {
my $schema = shift;

plan tests => 2;

my $rs1 = $schema->resultset("Artist")->search({ 'tags.tag' => 'Blue' }, { join => {'cds' => 'tracks'}, prefetch => {'cds' => 'tags'} });
my @artists = $rs1->all;
cmp_ok(@artists, '==', 1, "Two artists returned");

my $rs2 = $rs1->search({ artistid => '1' }, { join => {'cds' => {'cd_to_producer' => 'producer'} } });
my $rs3 = $rs2->search_related('cds')->search({'cds.title' => 'Forkful of bees'});
cmp_ok($rs3->count, '==', 3, "Three artists returned");

}
1;

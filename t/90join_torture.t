use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 6;

my @rs1a_results = $schema->resultset("Artist")->search_related('cds', {title => 'Forkful of bees'}, {order_by => 'title'});
is($rs1a_results[0]->title, 'Forkful of bees', "bare field conditions okay after search related");

my $rs1 = $schema->resultset("Artist")->search({ 'tags.tag' => 'Blue' }, { join => {'cds' => 'tracks'}, prefetch => {'cds' => 'tags'} });
my @artists = $rs1->all;
cmp_ok(@artists, '==', 1, "Two artists returned");

my $rs2 = $rs1->search({ artistid => '1' }, { join => {'cds' => {'cd_to_producer' => 'producer'} } });

my @artists2 = $rs2->search({ 'producer.name' => 'Matt S Trout' });
my @cds = $artists2[0]->cds;
cmp_ok(scalar @cds, '==', 1, "condition based on inherited join okay");

# this is wrong, should accept me.title really
my $rs3 = $rs2->search_related('cds')->search({'cds.title' => 'Forkful of bees'});

cmp_ok($rs3->count, '==', 3, "Three artists returned");

my $rs4 = $schema->resultset("CD")->search({ 'artist.artistid' => '1' }, { join => ['tracks', 'artist'], prefetch => 'artist' });
my @rs4_results = $rs4->all;


is($rs4_results[0]->cdid, 1, "correct artist returned");

my $rs5 = $rs4->search({'tracks.title' => 'Sticky Honey'});
is($rs5->count, 1, "search without using previous joins okay");

1;

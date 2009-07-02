use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 7;

my $schema = DBICTest->init_schema();

my $cd_rs = $schema->resultset('CD')->search (
  { 'tracks.cd' => { '!=', undef } },
  { prefetch => ['tracks', 'artist'] },
);


is($cd_rs->count, 5, 'CDs with tracks count');
is($cd_rs->search_related('tracks')->count, 15, 'Tracks associated with CDs count (before SELECT()ing)');

is($cd_rs->all, 5, 'Amount of CD objects with tracks');
is($cd_rs->search_related('tracks')->count, 15, 'Tracks associated with CDs count (after SELECT()ing)');

is($cd_rs->search_related ('tracks')->all, 15, 'Track objects associated with CDs (after SELECT()ing)');

my $artist=$schema->resultset('Artist')->create({name => 'xxx'});
my $artist_rs = $schema->resultset('Artist')->search({artistid => $artist->id}, {prefetch=>'cds'});
is($artist_rs->related_resultset('cds')->count, 0, "No CDs on a brand new artist");
is($artist_rs->count, 1,
   "No CDs prefetched but the artist is still returned");


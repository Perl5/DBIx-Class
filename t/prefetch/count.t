use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 9;

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
is($artist_rs->count, 1, "New artist found with prefetch turned on");
is(scalar($artist_rs->all), 1, "New artist fetched with prefetch turned on");
is($artist_rs->related_resultset('cds')->count, 0, "No CDs counted on a brand new artist");
is(scalar($artist_rs->related_resultset('cds')->all), 0, "No CDs fetched on a brand new artist (count == fetch)");


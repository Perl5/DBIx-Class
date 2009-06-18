# Test to ensure we get a consistent result set wether or not we use the
# prefetch option in combination rows (LIMIT).
use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 4;

my $schema = DBICTest->init_schema();


my $no_prefetch = $schema->resultset('Artist')->search(
  undef,
  { rows => 3 }
);

my $use_prefetch = $schema->resultset('Artist')->search(
  [   # search deliberately contrived
    { 'artwork.cd_id' => undef },
    { 'tracks.title' => { '!=' => 'blah-blah-1234568' }}
  ],
  {
    prefetch => 'cds',
    join => { cds => [qw/artwork tracks/] },
    rows     => 3,
    order_by => { -desc => 'name' },
  }
);

is($no_prefetch->count, $use_prefetch->count, '$no_prefetch->count == $use_prefetch->count');
is(
  scalar ($no_prefetch->all),
  scalar ($use_prefetch->all),
  "Amount of returned rows is right"
);

my $artist_many_cds = $schema->resultset('Artist')->search ( {}, {
  join => 'cds',
  group_by => 'me.artistid',
  having => \ 'count(cds.cdid) > 1',
})->first;


$no_prefetch = $schema->resultset('Artist')->search(
  { artistid => $artist_many_cds->id },
  { rows => 1 }
);

$use_prefetch = $schema->resultset('Artist')->search(
  { artistid => $artist_many_cds->id },
  {
    prefetch => 'cds',
    rows     => 1
  }
);

my $prefetch_artist = $use_prefetch->first;
my $normal_artist = $no_prefetch->first;

is(
  $prefetch_artist->cds->count,
  $normal_artist->cds->count,
  "Count of child rel with prefetch + rows => 1 is right"
);
is (
  scalar ($prefetch_artist->cds->all),
  scalar ($normal_artist->cds->all),
  "Amount of child rel rows with prefetch + rows => 1 is right"
);

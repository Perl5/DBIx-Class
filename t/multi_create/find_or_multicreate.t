use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema( no_populate => 1 );

my $t11 = $schema->resultset('Track')->find_or_create({
  trackid => 1,
  title => 'Track one cd one',
  cd => {
    year => 1,
    title => 'CD one',
    very_long_artist_relationship => {
      name => 'Artist one',
    }
  }
});

my $t12 = $schema->resultset('Track')->find_or_create({
  trackid => 2,
  title => 'Track two cd one',
  cd => {
    title => 'CD one',
    very_long_artist_relationship => {
      name => 'Artist one',
    }
  }
});

# FIXME - MC should be smart enough to infer this on its own...
$schema->resultset('Artist')->create({ name => 'Artist two' });

my $t2 = $schema->resultset('Track')->find_or_create({
  trackid => 3,
  title => 'Track one cd one',
  cd => {
    year => 1,
    title => 'CD one',
    very_long_artist_relationship => {
      name => 'Artist two',
    }
  }
});

is_deeply(
  $schema->resultset('Artist')->search({}, {
    prefetch => { cds => 'tracks' },
    order_by => 'tracks.title',
  })->all_hri,
  [
    { artistid => 1, charfield => undef, name => "Artist one", rank => 13, cds => [
      { artist => 1, cdid => 1, genreid => undef, single_track => undef, title => "CD one", year => 1, tracks => [
        { cd => 1, last_updated_at => undef, last_updated_on => undef, position => 1, title => "Track one cd one", trackid => 1 },
        { cd => 1, last_updated_at => undef, last_updated_on => undef, position => 2, title => "Track two cd one", trackid => 2 },
      ]},
    ]},
    { artistid => 2, charfield => undef, name => "Artist two", rank => 13, cds => [
      { artist => 2, cdid => 2, genreid => undef, single_track => undef, title => "CD one", year => 1, tracks => [
        { cd => 2, last_updated_at => undef, last_updated_on => undef, position => 1, title => "Track one cd one", trackid => 3 },
      ]},
    ]},
  ],
  'Expected state of database after several find_or_create rounds'
);


done_testing;


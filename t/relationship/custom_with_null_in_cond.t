use strict;
use warnings;

use Test::More;

use lib 't/lib';
use DBICTest;

my $schema = DBICTest->init_schema();

my $artist_rs = $schema->resultset('Artist');

for my $rel_rs(
  $artist_rs->search_related_rs(
    cds_without_genre => { artist => 1 }, { order_by => 'cdid' }
  ),
  $artist_rs->find(1)->search_related_rs(
    cds_without_genre => {}, { order_by => 'cdid' }
  ),
) {

  is_deeply(
    $rel_rs->all_hri,
    [
      {
        artist => 1,
        cdid => 2,
        genreid => undef,
        single_track => undef,
        title => "Forkful of bees",
        year => 2001
      },
      {
        artist => 1,
        cdid => 3,
        genreid => undef,
        single_track => undef,
        title => "Caterwaulin' Blues",
        year => 1997
      },
    ]
  );
}

done_testing;

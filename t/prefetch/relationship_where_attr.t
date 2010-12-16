use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
my $schema = DBICTest->init_schema();

{
  my $artist_with_year2001_cds = $schema->resultset('Artist')->find(1);
  is $artist_with_year2001_cds->year2001_cds->count, 1, 'artist has one cd from 2001 without prefetching';
}

{
  my $artist_with_year2001_cds = $schema->resultset('Artist')->find(1, { prefetch => 'year2001_cds' });
  is $artist_with_year2001_cds->year2001_cds->count, 1, 'artist has one cd from 2001 with prefetching';
}

done_testing;

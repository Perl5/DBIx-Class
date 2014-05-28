use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $artist = $schema->resultset ('Artist')->find ({artistid => 1});
is ($artist->cds->count, 3, 'Correct number of CDs');
is ($artist->cds->search_related ('genre')->count, 1, 'Only one of the cds has a genre');

$schema->is_executed_querycount( sub {
  my $pref = $schema->resultset ('Artist')
                     ->search ({ 'me.artistid' => $artist->id }, { prefetch => { cds => 'genre' } })
                      ->next;

  is ($pref->cds->count, 3, 'Correct number of CDs prefetched');
  is ($pref->cds->search_related ('genre')->count, 1, 'Only one of the prefetched cds has a prefetched genre');

}, 1, 'All happened within one query only');

done_testing;

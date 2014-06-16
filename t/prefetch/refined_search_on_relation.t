use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $art = $schema->resultset('Artist')->find(
  { 'me.artistid' => 1 },
  { prefetch => 'cds', order_by => { -desc => 'cds.year' } }
);

is (
  $art->cds->search({ year => 1999 })->next->year,
  1999,
  'Found expected CD with year 1999 after refined search',
);

is (
  $art->cds->count({ year => 1999 }),
  1,
  'Correct refined count',
);

# this still should emit no queries:
{
  my $queries = 0;
  my $orig_debug = $schema->storage->debug;
  $schema->storage->debugcb(sub { $queries++; });
  $schema->storage->debug(1);

  my $cds = $art->cds;
  is (
    $cds->count,
    3,
    'Correct prefetched count',
  );

  my @years = qw(2001 1999 1997);
  while (my $cd = $cds->next) {
    is (
      $cd->year,
      (shift @years),
      'Correct prefetched cd year',
    );
  }

  $schema->storage->debug($orig_debug);
  $schema->storage->debugcb(undef);

  is ($queries, 0, 'No queries on prefetched operations');
}

done_testing;

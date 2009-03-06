# Test to ensure we get a consistent result set wether or not we use the
# prefetch option in combination rows (LIMIT).
use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan $@ ? (skip_all => 'needs DBD::SQLite for testing') : (tests => 2);

my $schema = DBICTest->init_schema();
$schema->storage->debug(1);
my $no_prefetch = $schema->resultset('Artist')->search(
  undef,
  { rows => 3 }
);

my $use_prefetch = $schema->resultset('Artist')->search(
  undef,
  {
    prefetch => 'cds',
    rows     => 3
  }
);

my $no_prefetch_count  = 0;
my $use_prefetch_count = 0;

is($no_prefetch->count, $use_prefetch->count, '$no_prefetch->count == $use_prefetch->count');

TODO: {
  local $TODO = "This is a difficult bug to fix, workaround is not to use prefetch with rows";
  $no_prefetch_count++  while $no_prefetch->next;
  $use_prefetch_count++ while $use_prefetch->next;
  is(
    $no_prefetch_count,
    $use_prefetch_count,
    "manual row count confirms consistency"
    . " (\$no_prefetch_count == $no_prefetch_count, "
    . " \$use_prefetch_count == $use_prefetch_count)"
  );
}

__END__
The fix is to, when using prefetch, take the query and put it into a subquery
joined to the tables we're prefetching from. This might result in the same
table being joined once in the main subquery and once in the main query. This
may actually resolve other, unknown edgecase bugs. It is also the right way
to do prefetching. Optimizations can come later.

This means that:
  $foo_rs->search(
    { ... },
    {
      prefetch => 'bar',
      ...
    },
  );

becomes:
  my $temp = $foo_rs->search(
    { ... },
    {
      join => 'bar',
      ...
    },
  );
  $foo_rs->storage->schema->resultset('foo')->search(
    undef,
    {
      from => [
        { me => $temp->as_query },
      ],
      prefetch => 'bar',
    },
  );

Problem:
  * The prefetch->join change needs to happen ONLY IF there are conditions
    that depend on bar being joined.

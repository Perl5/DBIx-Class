use strict;
use warnings;
use Test::More;

use lib qw(t/lib);

BEGIN {
  eval { require Test::Memory::Cycle; require Devel::Cycle };
  if ($@ or Devel::Cycle->VERSION < 1.10) {
    plan skip_all => "leak test needs Test::Memory::Cycle and Devel::Cycle >= 1.10";
  };
}

use DBICTest;
use DBICTest::Schema;
use Scalar::Util ();

import Test::Memory::Cycle;

my $weak;

{
  my $s = $weak->{schema} = DBICTest->init_schema;
  memory_cycle_ok($s, 'No cycles in schema');

  my $rs = $weak->{resultset} = $s->resultset ('Artist');
  memory_cycle_ok($rs, 'No cycles in resultset');

  my $rsrc = $weak->{resultsource} = $rs->result_source;
  memory_cycle_ok($rsrc, 'No cycles in resultsource');

  my $row = $weak->{row} = $rs->first;
  memory_cycle_ok($row, 'No cycles in row');

  Scalar::Util::weaken ($_) for values %$weak;
  memory_cycle_ok($weak, 'No cycles in weak object collection');
}

for (keys %$weak) {
  ok (! $weak->{$_}, "No $_ leaks");
}

done_testing;

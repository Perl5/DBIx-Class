use strict;
use warnings;
use Test::More;

use lib qw(t/lib);

BEGIN {
  eval { require Test::Memory::Cycle; require Devel::Cycle };
  if ($@ or Devel::Cycle->VERSION < 1.10) {
    plan skip_all => "leak test needs Test::Memory::Cycle and Devel::Cycle >= 1.10";
  } else {
    plan tests => 1;
  }
}

use DBICTest;
use DBICTest::Schema;

import Test::Memory::Cycle;

my $s = DBICTest::Schema->clone;

memory_cycle_ok($s, 'No cycles in schema');

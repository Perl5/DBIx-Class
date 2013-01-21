package DBICTest::AntiPattern::TrueZeroLen;

use warnings;
use strict;

use overload
  'bool'   => sub { 1 },
  '""'     => sub { '' },
  fallback => 1
;

sub new { bless {}, shift }

1;

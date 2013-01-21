package DBICTest::AntiPattern::NullObject;

use warnings;
use strict;

use overload
  'bool'   => sub { 0 },
  '""'     => sub { '' },
  '0+'     => sub { 0 },
  fallback => 1
;

our $null = bless {}, __PACKAGE__;
sub AUTOLOAD { $null }

1;

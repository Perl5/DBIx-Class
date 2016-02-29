package #hide from pause
  DBICTest::Base;

use strict;
use warnings;

use DBICTest::Util;

sub _skip_namespace_frames { '^DBICTest' }

1;

package #hide from pause
  DBICTest::Base;

use strict;
use warnings;

use DBICTest::Util;

# FIXME - Carp::Skip should somehow allow for augmentation based on
# mro::get_linear_isa or somesuch...
sub _skip_namespace_frames { '^DBICTest' }

1;

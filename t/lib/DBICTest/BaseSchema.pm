package #hide from pause
  DBICTest::BaseSchema;

use strict;
use warnings;

# must load before any DBIx::Class* namespaces
use DBICTest::RunMode;

use base 'DBIx::Class::Schema';

1;

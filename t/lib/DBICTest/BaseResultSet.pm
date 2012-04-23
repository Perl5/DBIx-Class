package #hide from pause
  DBICTest::BaseResultSet;

use strict;
use warnings;

# must load before any DBIx::Class* namespaces
use DBICTest::RunMode;

use base 'DBIx::Class::ResultSet';

sub all_hri {
  return [ shift->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' })->all ];
}

1;

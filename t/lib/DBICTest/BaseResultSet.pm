package #hide from pause
  DBICTest::BaseResultSet;

use strict;
use warnings;

use base qw(DBICTest::Base DBIx::Class::ResultSet);

sub all_hri {
  return [ shift->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' })->all ];
}

1;

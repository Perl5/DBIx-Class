#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib t/lib);

use DBICTest::Schema;
use SQL::Translator;

my $schema = DBICTest::Schema->connect;
print scalar ($schema->storage->deployment_statements(
  $schema,
  'SQLite',
  undef,
  undef,
  { producer_args => { no_transaction => 1 } }
));

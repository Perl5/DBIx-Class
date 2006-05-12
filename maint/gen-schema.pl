#!/usr/bin/perl

use strict;
use warnings;
use lib qw(lib t/lib);

use DBICTest::Schema;

my $schema = DBICTest::Schema->connect;

print $schema->storage->deployment_statements($schema, 'SQLite');

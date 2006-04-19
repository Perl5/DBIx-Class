#!/usr/bin/perl

use strict;
use warnings;
use lib qw(lib t/lib);

use DBICTest;
use DBICTest::Schema::HelperRels;

my $schema = DBICTest->initialise;

print $schema->storage->deployment_statements($schema);

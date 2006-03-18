#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest::ForeignComponent;

plan tests => 1;

#   Tests if foreign component was loaded by calling foreign's method
ok( DBICTest::ForeignComponent->foreign_test_method, 'foreign component' );


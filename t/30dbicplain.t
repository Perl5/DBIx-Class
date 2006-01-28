#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
eval 'use DBICTest::Plain; 1'
  or plan skip_all => 'Install Catalyst::Model::DBIC::Plain to run this test';

plan tests => 1;

cmp_ok(DBICTest::Plain->resultset('Test')->count, '>', 0, 'count is valid');

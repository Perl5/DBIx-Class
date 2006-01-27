#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

eval 'use Catalyst::Model::DBIC::Plain; 1'
  or plan skip_all => 'Install Catalyst::Model::DBIC::Plain to run this test';
plan tests => 1;

use lib qw(t/lib);
use DBICTest::Plain;

cmp_ok(DBICTest::Plain->resultset('Test')->count, '>', 0, 'count is valid');

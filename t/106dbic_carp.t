#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Warn;
use DBIx::Class::Carp;
use lib 't/lib';
use DBICTest;

warnings_exist {
  DBIx::Class::frobnicate();
} [
  qr/carp1/,
  qr/carp2/,
], 'expected warnings from carp_once';

done_testing;

sub DBIx::Class::frobnicate {
  DBIx::Class::branch1();
  DBIx::Class::branch2();
}

sub DBIx::Class::branch1 { carp_once 'carp1' }
sub DBIx::Class::branch2 { carp_once 'carp2' }

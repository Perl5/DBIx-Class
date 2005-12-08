#!/usr/bin/perl

use Test::More tests => 1;

eval {
  package BuggyTable;
  use base 'DBIx::Class';

  __PACKAGE__->load_components qw/Core/;
  __PACKAGE__->columns qw/this doesnt work as expected/;
};

like($@,qr/^columns\(\) is a read-only/,
     "columns() error when apparently misused");

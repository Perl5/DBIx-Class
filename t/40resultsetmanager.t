#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib qw(t/lib);

BEGIN {
  eval { require Class::Inspector; require Module::Find };
  if ($@ =~ m{Can.t locate Class/Inspector.pm}) {
    plan skip_all => "ResultSetManager requires Class::Inspector and Module::Find";
  } else {
    plan tests => 4;
  }
}

use DBICTest::Extra; # uses Class::Inspector

my $schema = DBICTest::Extra->compose_connection('DB', 'foo');
my $rs = $schema->resultset('Foo');

ok( !DB::Foo->can('bar'), 'Foo class does not have bar method' );
ok( $rs->can('bar'), 'Foo resultset class has bar method' );
isa_ok( $rs, 'DBICTest::Extra::Foo::_resultset', 'Foo resultset class is correct' );
is( $rs->bar, 'good', 'bar method works' );

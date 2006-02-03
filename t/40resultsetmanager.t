#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest::Extra;

plan tests => 4;

my $schema = DBICTest::Extra->compose_connection('DB', 'foo');
my $rs = $schema->resultset('Foo');

ok( !DB::Foo->can('bar'), 'Foo class does not have bar method' );
ok( $rs->can('bar'), 'Foo resultset class has bar method' );
isa_ok( $rs, 'DBICTest::Extra::Foo::_resultset', 'Foo resultset class is correct' );
is( $rs->bar, 'good', 'bar method works' );
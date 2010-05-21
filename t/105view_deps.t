#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use Devel::Dwarn;
use ViewDeps;

BEGIN {
    use_ok('DBIx::Class::ResultSource::View');
}

my $view = DBIx::Class::ResultSource::View->new( { name => 'Quux' } );

isa_ok( $view, 'DBIx::Class::ResultSource' );
isa_ok( $view, 'DBIx::Class' );

can_ok( $view, $_ ) for qw/new from depends_on/;

#################################

my $schema = ViewDeps->connect;
ok( $schema, 'Connected to ViewDeps schema OK' );

my @bar_deps = keys %{ $schema->resultset('Bar')->result_source->depends_on };

my @foo_deps = keys %{ $schema->resultset('Foo')->result_source->depends_on };

isa_ok( $schema->resultset('Bar')->result_source,
    'DBIx::Class::ResultSource::View', 'Bar' );

is( $bar_deps[0], 'mixin', 'which is reported to depend on mixin.' );
is( $foo_deps[0], undef,   'Foo has no dependencies...' );

isa_ok(
    $schema->resultset('Foo')->result_source,
    'DBIx::Class::ResultSource::View',
    'though Foo'
);
#diag($schema->resultset('Baz')->result_source->table_class);
isa_ok($schema->resultset('Baz')->result_source, 'DBIx::Class::ResultSource::Table', "Baz on the other hand");
dies_ok {  ViewDeps::Result::Baz->result_source_instance->depends_on(
        { ViewDeps::Result::Mixin->result_source_instance->name => 1 }
    ) } "...and you cannot use depends_on with that";

done_testing;

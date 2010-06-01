#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use ViewDeps;
use Devel::Dwarn;
use Data::Dumper;

BEGIN {
    use_ok('DBIx::Class::ResultSource::View');
}

### SANITY

my $view = DBIx::Class::ResultSource::View->new( { name => 'Quux' } );

isa_ok( $view, 'DBIx::Class::ResultSource', 'A new view' );
isa_ok( $view, 'DBIx::Class', 'A new view also' );

can_ok( $view, $_ ) for qw/new from deploy_depends_on/;

### DEPS

my $schema = ViewDeps->connect;
ok( $schema, 'Connected to ViewDeps schema OK' );

my $deps_ref = {
    map {
        $schema->resultset($_)->result_source->source_name =>
            $schema->resultset($_)->result_source->deploy_depends_on
        }
        grep {
        $schema->resultset($_)
            ->result_source->isa('DBIx::Class::ResultSource::View')
        } @{ [ $schema->sources ] }
};

diag( Dwarn $deps_ref);


#isa_ok( $schema->resultset('Bar')->result_source,
#'DBIx::Class::ResultSource::View', 'Bar' );

#is( $bar_deps[0], 'baz',   'which is reported to depend on baz...' );
#is( $bar_deps[1], 'mixin', 'and on mixin.' );
#is( $foo_deps[0], undef,   'Foo has no declared dependencies...' );

#isa_ok(
#$schema->resultset('Foo')->result_source,
#'DBIx::Class::ResultSource::View',
#'though Foo'
#);
#isa_ok(
#$schema->resultset('Baz')->result_source,
#'DBIx::Class::ResultSource::Table',
#"Baz on the other hand"
#);
#dies_ok {
#ViewDeps::Result::Baz->result_source_instance
#->deploy_depends_on("ViewDeps::Result::Mixin");
#}
#"...and you cannot use deploy_depends_on with that";

### DEPLOY

my $dir = "t/sql";
$schema->create_ddl_dir( [ 'PostgreSQL', 'SQLite' ], 0.1, $dir );

done_testing;

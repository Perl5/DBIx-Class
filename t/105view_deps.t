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

my $view = DBIx::Class::ResultSource::View->new( { name => 'Upsilon' } );
isa_ok( $view, 'DBIx::Class::ResultSource' );
isa_ok( $view, 'DBIx::Class' );

can_ok( $view, $_ ) for qw/new from depends_on/;

diag( map {"$_\n"} @{ mro::get_linear_isa($view) } );
#diag( DwarnS $view);

my $schema = ViewDeps->connect;
ok($schema);

#diag(DwarnS $schema);

#diag(DwarnS $schema->resultset('Bar')->result_source->depends_on);
diag keys %{$schema->resultset('Bar')->result_source->depends_on};
my @dependencies = keys %{$schema->resultset('Bar')->result_source->depends_on};
is($dependencies[0], 'mixin');

done_testing;

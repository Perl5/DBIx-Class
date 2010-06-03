#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use ViewDeps;

BEGIN {
    use_ok('DBIx::Class::ResultSource::View');
}

#################### SANITY

my $view = DBIx::Class::ResultSource::View->new( { name => 'Quux' } );

isa_ok( $view, 'DBIx::Class::ResultSource', 'A new view' );
isa_ok( $view, 'DBIx::Class', 'A new view also' );

can_ok( $view, $_ ) for qw/new from deploy_depends_on/;

#################### DEPS

my $schema
    = ViewDeps->connect( 'dbi:SQLite::memory:', { quote_char => '"', } );
ok( $schema, 'Connected to ViewDeps schema OK' );

my $deps_ref = {
    map {
        $schema->resultset($_)->result_source->name =>
            $schema->resultset($_)->result_source->deploy_depends_on
        }
        grep {
        $schema->resultset($_)
            ->result_source->isa('DBIx::Class::ResultSource::View')
        } @{ [ $schema->sources ] }
};

my @sorted_sources = sort {
    keys %{ $deps_ref->{$a} || {} } <=> keys %{ $deps_ref->{$b} || {} }
        || $a cmp $b
    }
    keys %$deps_ref;

#################### DEPLOY

$schema->deploy( { add_drop_table => 1 } );

#################### DOES ORDERING WORK?

my $tr = $schema->{sqlt};

my @keys = keys %{ $tr->{views} };

my @sqlt_sources
    = sort { $tr->{views}->{$a}->{order} cmp $tr->{views}->{$b}->{order} }
    @keys;

is_deeply( \@sorted_sources, \@sqlt_sources,
    "SQLT view order triumphantly matches our order." );

#################### AND WHAT ABOUT USING THE SCHEMA?

lives_ok( sub { $schema->resultset($_)->next }, "Query on $_ succeeds" )
    for grep {
    $schema->resultset($_)
        ->result_source->isa('DBIx::Class::ResultSource::View')
    } @{ [ $schema->sources ] };

done_testing;

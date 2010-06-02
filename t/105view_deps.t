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

my @sql_files = glob("t/sql/ViewDeps*.sql");
for (@sql_files) {
    ok( unlink($_), "Deleted old SQL $_ OK" );
}

my $schema = ViewDeps->connect( 'dbi:SQLite::memory:',
    { quote_char => '"', } );
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

my @sorted_sources =
    sort {
        keys %{ $deps_ref->{$a} || {} }
        <=>
        keys %{ $deps_ref->{$b} || {} }
        || $a cmp $b
    }
    keys %$deps_ref;

#################### DEPLOY

my $ddl_dir = "t/sql";
$schema->create_ddl_dir( [ 'PostgreSQL', 'MySQL', 'SQLite' ], 0.1, $ddl_dir );

ok( -e $_, "$_ was created successfully" ) for @sql_files;

$schema->deploy( { add_drop_table => 1 } );

#################### DOES ORDERING WORK?

my $tr = $schema->{sqlt};

my @keys = keys %{$tr->{views}};

my @sqlt_sources = 
    sort {
        $tr->{views}->{$a}->{order}
        cmp
        $tr->{views}->{$b}->{order}
    }
    @keys;

is_deeply(\@sorted_sources,\@sqlt_sources,"SQLT view order triumphantly matches our order.");

#################### AND WHAT ABOUT USING THE SCHEMA?

my $a_name_rs = $schema->resultset('ANameArtists');
my $ab_name_rs = $schema->resultset('AbNameArtists');
my $aba_name_rs = $schema->resultset('AbaNameArtists');
my $aba_name_cds_rs = $schema->resultset('AbaNameArtistsAnd2010CDsWithManyTracks');
my $track_five_rs = $schema->resultset('TrackNumberFives');
my $year_2010_rs = $schema->resultset('Year2010CDs');
my $year_2010_cds_rs = $schema->resultset('Year2010CDsWithManyTracks');

ok($a_name_rs, "ANameArtists resultset is OK");
ok($ab_name_rs, "AbNameArtists resultset is OK");
ok($aba_name_rs, "AbaNameArtists resultset is OK");
ok($aba_name_cds_rs, "AbaNameArtistsAnd2010CDsWithManyTracks resultset is OK");
ok($track_five_rs, "TrackNumberFives resultset is OK");
ok($year_2010_rs, "Year2010CDs resultset is OK");
ok($year_2010_cds_rs, "Year2010CDsWithManyTracks resultset is OK");

done_testing;

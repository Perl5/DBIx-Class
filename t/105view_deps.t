#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;
use ViewDeps;
use ViewDepsBad;

BEGIN {
    require DBIx::Class;
    plan skip_all => 'Test needs ' .
        DBIx::Class::Optional::Dependencies->req_missing_for('deploy')
      unless DBIx::Class::Optional::Dependencies->req_ok_for('deploy');
}

use_ok('DBIx::Class::ResultSource::View');

#################### SANITY

my $view = DBIx::Class::ResultSource::View->new;

isa_ok( $view, 'DBIx::Class::ResultSource', 'A new view' );
isa_ok( $view, 'DBIx::Class', 'A new view also' );

can_ok( $view, $_ ) for qw/new from deploy_depends_on/;

#################### DEPS
{
  my $schema
    = ViewDeps->connect( DBICTest->_database (quote_char => '"') );
  ok( $schema, 'Connected to ViewDeps schema OK' );

#################### DEPLOY

  $schema->deploy( { add_drop_table => 1 } );

#################### DOES ORDERING WORK?

  my $sqlt_object = $schema->{sqlt};

  is_deeply(
    [ map { $_->name } $sqlt_object->get_views ],
    [qw/
      a_name_artists
      track_number_fives
      year_2010_cds
      ab_name_artists
      year_2010_cds_with_many_tracks
      aba_name_artists
      aba_name_artists_and_2010_cds_with_many_tracks
    /],
    "SQLT view order triumphantly matches our order."
  );

#################### AND WHAT ABOUT USING THE SCHEMA?

  lives_ok( sub { $schema->resultset($_)->next }, "Query on $_ succeeds" )
    for grep {
    $schema->resultset($_)
      ->result_source->isa('DBIx::Class::ResultSource::View')
    } @{ [ $schema->sources ] };
}

#################### AND WHAT ABOUT A BAD DEPS CHAIN IN A VIEW?

{
  my $schema2
    = ViewDepsBad->connect( DBICTest->_database ( quote_char => '"') );
  ok( $schema2, 'Connected to ViewDepsBad schema OK' );

#################### DEPLOY2

  warnings_exist { $schema2->deploy( { add_drop_table => 1 } ) }
    [qr/no such table: main.aba_name_artists/],
    "Deploying the bad schema produces a warning: aba_name_artists was not created.";

#################### DOES ORDERING WORK 2?

  my $sqlt_object2 = $schema2->{sqlt};

  is_deeply(
    [ map { $_->name } $sqlt_object2->get_views ],
    [qw/
      a_name_artists
      track_number_fives
      year_2010_cds
      ab_name_artists
      year_2010_cds_with_many_tracks
      aba_name_artists_and_2010_cds_with_many_tracks
      aba_name_artists
    /],
    "SQLT view order triumphantly matches our order."
  );

#################### AND WHAT ABOUT USING THE SCHEMA2?

  lives_ok( sub { $schema2->resultset($_)->next }, "Query on $_ succeeds" )
    for grep {
    $schema2->resultset($_)
      ->result_source->isa('DBIx::Class::ResultSource::View')
    } grep { !/AbaNameArtistsAnd2010CDsWithManyTracks/ }
    @{ [ $schema2->sources ] };

  throws_ok { $schema2->resultset('AbaNameArtistsAnd2010CDsWithManyTracks')->next }
    qr/no such table: aba_name_artists_and_2010_cds_with_many_tracks/,
    "Query on AbaNameArtistsAnd2010CDsWithManyTracks throws, because the table does not exist"
  ;
}

done_testing;

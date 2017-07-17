BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'deploy';

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;

use DBICTest;
use ViewDeps;
use ViewDepsBad;

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

  $schema->deploy;

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

  my $lazy_view_validity = !(
    $schema2->storage->_server_info->{normalized_dbms_version}
      <
    3.009
  );

#################### DEPLOY2

  warnings_exist { $schema2->deploy }
    [ $lazy_view_validity ? () : qr/no such table: main.aba_name_artists/ ],
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

  $schema2->storage->dbh->do(q( DROP VIEW "aba_name_artists" ))
    if $lazy_view_validity;

  throws_ok { $schema2->resultset('AbaNameArtistsAnd2010CDsWithManyTracks')->next }
    qr/no such table: (?:main\.)?aba_name_artists/,
    sprintf(
      "Query on AbaNameArtistsAnd2010CDsWithManyTracks throws, because the%s view does not exist",
      $lazy_view_validity ? ' underlying' : ''
    )
  ;
}

done_testing;

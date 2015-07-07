BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;

my $schema = DBICTest->init_schema( no_deploy => 1 );

my $artist = $schema->resultset('Artist')->new_result({ artistid => 1 });

throws_ok {
  $schema->resultset('ArtistUndirectedMap')->find({
    mapped_artists => $artist,
  });
} qr/\QUnable to complete value inferrence - relationship 'mapped_artists' on source 'ArtistUndirectedMap' results in expression(s) instead of definitive values: ( id1 = ? OR id2 = ? )/,
  'proper exception on OR relationship inferrence'
;

throws_ok {
  $schema->resultset('Artwork_to_Artist')->find({
    artist_limited_rank_opaque => $artist
  })
} qr/\QRelationship 'artist_limited_rank_opaque' on source 'Artwork_to_Artist' does not resolve to a 'foreign_values'-based reversed-join-free condition fragment/,
  'proper exception on ipaque custom cond'
;

done_testing;

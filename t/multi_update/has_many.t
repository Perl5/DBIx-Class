use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $track_no_lyrics = $schema->resultset ('Track')
              ->search ({ 'lyrics.lyric_id' => undef }, { join => 'lyrics' })
                ->first;

my $lyric = $track_no_lyrics->create_related ('lyrics', {
  lyric_versions => [
    { text => 'english doubled' },
    { text => 'english doubled' },
  ],
});
is ($lyric->lyric_versions->count, 2, "Two identical has_many's created");

# should the lyric_versions have pks? just replace them all?
# this tries to do a create
$track_no_lyrics = $schema->resultset('Track')->update_or_create( { 
  trackid => $track_no_lyrics->trackid,
  title => 'Titled Updated by Multi Update',
  lyrics => {
    lyric_versions => [ 
      { text => 'Some new text' },
      { text => 'Other text' },
    ],
  },
});
is( $track_no_lyrics->title, 'Title Updated by Multi Update', 'title updated' );
is( $track_no_lyrics->lyrics->search_related('lyric_versions', { text => 'Other text' } )->count, 1, 'related record updated' );


done_testing;

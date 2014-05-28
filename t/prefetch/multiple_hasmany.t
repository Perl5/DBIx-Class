use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

#( 1 -> M + M )
my $cd_rs = $schema->resultset('CD')->search( { 'me.title' => 'Forkful of bees' } );
my $pr_cd_rs = $cd_rs->search( {}, { prefetch => [qw/tracks tags/], } );

my $tracks_rs    = $cd_rs->first->tracks;
my $tracks_count = $tracks_rs->count;

$schema->is_executed_querycount( sub {
  my $pcr = $pr_cd_rs;
  my $pr_tracks_rs;

  warnings_exist {
    $pr_tracks_rs = $pcr->first->tracks;
  } [], 'no warning on attempt to prefetch several same level has_many\'s (1 -> M + M)' ;

  is( $pr_tracks_rs->count, $tracks_count,
    'equal count of prefetched relations over several same level has_many\'s (1 -> M + M)'
  );

  is( $pr_tracks_rs->all, $tracks_count,
    'equal amount of objects returned with and without prefetch over several same level has_many\'s (1 -> M + M)'
  );

}, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query' );


#( M -> 1 -> M + M )
my $note_rs =
  $schema->resultset('LinerNotes')->search( { notes => 'Buy Whiskey!' } );
my $pr_note_rs =
  $note_rs->search( {}, { prefetch => { cd => [qw/tracks tags/] }, } );

my $tags_rs    = $note_rs->first->cd->tags;
my $tags_count = $tags_rs->count;

$schema->is_executed_querycount( sub {
  my $pnr = $pr_note_rs;
  my $pr_tags_rs;

  warnings_exist {
    $pr_tags_rs = $pnr->first->cd->tags;
  } [], 'no warning on attempt to prefetch several same level has_many\'s (M -> 1 -> M + M)';

  is( $pr_tags_rs->count, $tags_count,
    'equal count of prefetched relations over several same level has_many\'s (M -> 1 -> M + M)'
  );
  is( $pr_tags_rs->all, $tags_count,
    'equal amount of objects with and without prefetch over several same level has_many\'s (M -> 1 -> M + M)'
  );

}, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query' );


done_testing;

use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
my $sdebug = $schema->storage->debug;

#( 1 -> M + M )
my $cd_rs = $schema->resultset('CD')->search( { 'me.title' => 'Forkful of bees' } );
my $pr_cd_rs = $cd_rs->search( {}, { prefetch => [qw/tracks tags/], } );

my $tracks_rs    = $cd_rs->first->tracks;
my $tracks_count = $tracks_rs->count;

my ( $pr_tracks_rs, $pr_tracks_count );

my $queries = 0;
$schema->storage->debugcb( sub { $queries++ } );
$schema->storage->debug(1);

my $o_mm_warn;
{
    local $SIG{__WARN__} = sub { $o_mm_warn = shift };
    $pr_tracks_rs = $pr_cd_rs->first->tracks;
};
$pr_tracks_count = $pr_tracks_rs->count;

ok( !$o_mm_warn,
'no warning on attempt to prefetch several same level has_many\'s (1 -> M + M)'
);

is( $queries, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query' );
$schema->storage->debugcb(undef);
$schema->storage->debug($sdebug);

is( $pr_tracks_count, $tracks_count,
'equal count of prefetched relations over several same level has_many\'s (1 -> M + M)'
);
is( $pr_tracks_rs->all, $tracks_rs->all,
'equal amount of objects returned with and without prefetch over several same level has_many\'s (1 -> M + M)'
);

#( M -> 1 -> M + M )
my $note_rs =
  $schema->resultset('LinerNotes')->search( { notes => 'Buy Whiskey!' } );
my $pr_note_rs =
  $note_rs->search( {}, { prefetch => { cd => [qw/tracks tags/] }, } );

my $tags_rs    = $note_rs->first->cd->tags;
my $tags_count = $tags_rs->count;

my ( $pr_tags_rs, $pr_tags_count );

$queries = 0;
$schema->storage->debugcb( sub { $queries++ } );
$schema->storage->debug(1);

my $m_o_mm_warn;
{
    local $SIG{__WARN__} = sub { $m_o_mm_warn = shift };
    $pr_tags_rs = $pr_note_rs->first->cd->tags;
};
$pr_tags_count = $pr_tags_rs->count;

ok( !$m_o_mm_warn,
'no warning on attempt to prefetch several same level has_many\'s (M -> 1 -> M + M)'
);

is( $queries, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query' );
$schema->storage->debugcb(undef);
$schema->storage->debug($sdebug);

is( $pr_tags_count, $tags_count,
'equal count of prefetched relations over several same level has_many\'s (M -> 1 -> M + M)'
);
is( $pr_tags_rs->all, $tags_rs->all,
'equal amount of objects with and without prefetch over several same level has_many\'s (M -> 1 -> M + M)'
);

done_testing;

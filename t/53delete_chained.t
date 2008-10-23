use Test::More;
use strict;
use warnings;
use lib qw(t/lib);
use DBICTest;

plan tests => 9;

# This set of tests attempts to do a delete on a chained resultset, which
# would lead to SQL DELETE with a JOIN, which is not supported by the 
# SQL generator right now.
# So it currently checks that these operations fail with a warning.
# When the SQL generator is fixed this test will need fixing up appropriately.

my $schema = DBICTest->init_schema();
my $total_tracks = $schema->resultset('Track')->count;
cmp_ok($total_tracks, '>', 0, 'need track records');

# test that delete_related w/o conditions deletes all related records only
{
  my $w;
  local $SIG{__WARN__} = sub { $w = shift };

  my $artist = $schema->resultset("Artist")->find(3);
  my $artist_tracks = $artist->cds->search_related('tracks')->count;
  cmp_ok($artist_tracks, '<', $total_tracks, 'need more tracks than just related tracks');

  ok(!eval{$artist->cds->search_related('tracks')->delete});
  cmp_ok($schema->resultset('Track')->count, '==', $total_tracks, 'No tracks should be deleted');
  like ($w, qr/Currently \$rs->delete\(\) does not generate proper SQL/, 'Delete join warning');
}

# test that delete_related w/conditions deletes just the matched related records only
{
  my $w;
  local $SIG{__WARN__} = sub { $w = shift };

  my $artist2 = $schema->resultset("Artist")->find(2);
  my $artist2_tracks = $artist2->search_related('cds')->search_related('tracks')->count;
  cmp_ok($artist2_tracks, '<', $total_tracks, 'need more tracks than related tracks');
  
  ok(!eval{$artist2->search_related('cds')->search_related('tracks')->delete});
  cmp_ok($schema->resultset('Track')->count, '==', $total_tracks, 'No tracks should be deleted');
  like ($w, qr/Currently \$rs->delete\(\) does not generate proper SQL/, 'Delete join warning');
}

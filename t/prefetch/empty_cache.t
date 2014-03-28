use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $no_albums_artist = { name => 'We Have No Albums' };
$schema->resultset('Artist')->create($no_albums_artist);

foreach (
  [empty => \'0 = 1', 0],
  [nonempty => $no_albums_artist, 1],
) {
  my ($desc, $cond, $count) = @$_;

  my $artists_rs = $schema->resultset('Artist')
    ->search($cond, { prefetch => 'cds', cache => 1 });

  $schema->is_executed_querycount( sub {
    my @artists = $artists_rs->all;
    is( 0+@{$artists_rs->get_cache}, $count, "$desc cache on original resultset" );
    is( 0+@artists, $count, "$desc original resultset" );
  }, 1, "->all on $desc original resultset hit db" );

  $schema->is_executed_querycount( sub {
    my $cds_rs = $artists_rs->related_resultset('cds');
    is_deeply( $cds_rs->get_cache, [], 'empty cache on related resultset' );

    my @cds = $cds_rs->all;
    is( 0+@cds, 0, 'empty related resultset' );
  }, 0, '->all on empty related resultest didn\'t hit db' );
}


done_testing;

use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $queries;
my $debugcb = sub { $queries++; };
my $orig_debug = $schema->storage->debug;

{
  $queries = 0;
  $schema->storage->debugcb($debugcb);
  $schema->storage->debug(1);

  my $cds_rs = $schema->resultset('CD')
    ->search(\'0 = 1', { prefetch => 'tracks', cache => 1 });

  my @cds = $cds_rs->all;
  is( $queries, 1, '->all on empty original resultset hit db' );
  is_deeply( $cds_rs->get_cache, [], 'empty cache on original resultset' );
  is( 0+@cds, 0, 'empty original resultset' );

  my $tracks_rs = $cds_rs->related_resultset('tracks');
  is_deeply( $tracks_rs->get_cache, [], 'empty cache on related resultset' );

  my @tracks = $tracks_rs->all;
  is( $queries, 1, "->all on empty related resultset didn't hit db" );
  is( 0+@tracks, 0, 'empty related resultset' );

  $schema->storage->debugcb(undef);
  $schema->storage->debug($orig_debug);
}

done_testing;

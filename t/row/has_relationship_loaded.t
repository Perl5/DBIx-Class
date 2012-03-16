use strict;
use warnings;

use lib qw(t/lib);
use Test::More;
use Test::Exception;
use DBICTest;

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset('CD');
my $row = $rs->first;

dies_ok { $row->has_relationship_loaded() }
  'has_relationship_loaded needs a relationship name';

ok !$row->has_relationship_loaded($_), "vanilla row has no loaded relationship '$_'"
  for $row->result_source->relationships;

# Prefetch of single relationship
{
  my $prefetched = $rs->search_rs(undef, { prefetch => 'artist' })->first;
  ok $prefetched->has_relationship_loaded('artist'), 'single prefetch detected by has_relationship_loaded';
}

# Prefetch of multiple relationships
{
  my $prefetched = $rs->search_rs(undef, { prefetch => ['artist', 'tracks'] })->first;
  ok $prefetched->has_relationship_loaded('artist'), 'first prefetch detected by has_relationship_loaded';
  ok $prefetched->has_relationship_loaded('tracks'), 'second prefetch detected by has_relationship_loaded';
}

# Prefetch of nested relationships
{
  my $prefetched = $rs->search_rs(undef, { prefetch => {'artist' => 'artwork_to_artist'} })->first;
  ok $prefetched->has_relationship_loaded('artist'), 'direct prefetch detected by has_relationship_loaded';
  ok $prefetched->artist->has_relationship_loaded('artwork_to_artist'), 'nested prefetch detected by has_relationship_loaded';
}

done_testing;

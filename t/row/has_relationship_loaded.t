use strict;
use warnings;

use lib qw(t/lib);
use Test::More;
use Test::Exception;
use Data::Dumper::Concise;
local $Data::Dumper::Maxdepth = 3;
use DBICTest;

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset('CD');
my $row = $rs->new_result({});

dies_ok { $row->has_relationship_loaded() }
  'has_relationship_loaded needs a relationship name';

ok !$row->has_relationship_loaded($_), "vanilla row has no loaded relationship '$_'"
  for $row->result_source->relationships;

# Prefetch of single belongs_to relationship
{
  my $prefetched_rs = $rs->search_rs(undef, { prefetch => 'artist' });
  my $cd = $prefetched_rs->find(1);
  ok $cd->has_relationship_loaded('artist'), 'belongs_to relationship with related row detected by has_relationship_loaded';
}

# Prefetch of single might_have relationship
{
  my $prefetched_rs = $rs->search_rs(undef, { prefetch => 'liner_notes' });
  my $cd_without_liner_notes = $prefetched_rs->find(1);
  ok $cd_without_liner_notes->has_relationship_loaded('liner_notes'), 'might_have relationship without related row detected by has_relationship_loaded';
  my $cd_with_liner_notes = $prefetched_rs->find(2);
  ok $cd_with_liner_notes->has_relationship_loaded('liner_notes'), 'might_have relationship with related row detected by has_relationship_loaded';
}

# Prefetch of single has_many relationship
{
  my $prefetched_rs = $rs->search_rs(undef, { prefetch => 'tracks' });
  my $cd_with_tracks = $prefetched_rs->find(2);
  ok $cd_with_tracks->has_relationship_loaded('tracks'), 'has_many relationship with related rows detected by has_relationship_loaded';

  # New without related rows
  my $new_cd_without_tracks = $rs->create({
    artist => 1,
    title  => 'Empty CD',
    year   => 2012,
  });
  ok !$new_cd_without_tracks->has_relationship_loaded('tracks'), 'has_many relationship without related rows for new object detected by has_relationship_loaded';

  my $new_cd_with_tracks = $rs->create({
    artist => 1,
    title  => 'Non-empty CD',
    year   => 2012,
    tracks => [
      {
        position => 1,
        title    => 'first track',
      },
      {
        position => 2,
        title    => 'second track',
      },
    ],
  });

  ok $new_cd_with_tracks->has_relationship_loaded('tracks'), 'has_many relationship with related rows for new object detected by has_relationship_loaded';

  my $cd_without_tracks = $prefetched_rs->find($new_cd_without_tracks->id);
  ok $cd_without_tracks->has_relationship_loaded('tracks'), 'has_many relationship without related rows detected by has_relationship_loaded';
}

# Prefetch of multiple relationships
{
  my $prefetched = $rs->search_rs(undef, { prefetch => ['artist', 'tracks'] })->find(1);
  ok $prefetched->has_relationship_loaded('artist'), 'first prefetch detected by has_relationship_loaded';
  ok $prefetched->has_relationship_loaded('tracks'), 'second prefetch detected by has_relationship_loaded';
  ok !$prefetched->tracks->first->has_relationship_loaded('single_cd'), 'nested not prefetched rel detected by has_relationship_loaded';
}

# Prefetch of nested relationships
{
  my $prefetched = $schema->resultset('Artist')->search_rs(undef, { prefetch => {'cds' => 'tracks'} })->find(1);
  ok $prefetched->has_relationship_loaded('cds'), 'direct prefetch detected by has_relationship_loaded';
  ok $prefetched->cds->first->has_relationship_loaded('tracks'), 'nested prefetch detected by has_relationship_loaded';
  ok !$prefetched->cds->first->has_relationship_loaded('single_track'), 'nested not prefetched rel detected by has_relationship_loaded';
}

# Multinew
{
  my $cd_with_tracks = $rs->new({
    artist => 1,
    title  => 'CD with tracks',
    year   => 2012,
    tracks => [
      {
        position => 1,
        title    => 'first track',
      },
      {
        position => 2,
        title    => 'second track',
      },
    ],
  });
  ok !$cd_with_tracks->has_relationship_loaded('artist'), 'multinew: not created rel detected by has_relationship_loaded';
  ok $cd_with_tracks->has_relationship_loaded('tracks'), 'multinew: created rel detected by has_relationship_loaded';
  # fails because $cd_with_tracks->tracks->first returns undef
  # ok !$cd_with_tracks->tracks->first->has_relationship_loaded('cd'), 'multinew: nested not created rel detected by has_relationship_loaded';
}

# Multicreate
{
  my $cd_with_tracks = $rs->create({
    artist => 1,
    title  => 'CD with tracks',
    year   => 2012,
    tracks => [
      {
        position => 1,
        title    => 'first track',
      },
      {
        position => 2,
        title    => 'second track',
      },
    ],
  });
  ok !$cd_with_tracks->has_relationship_loaded('artist'), 'multicreate: not created rel detected by has_relationship_loaded';
  ok $cd_with_tracks->has_relationship_loaded('tracks'), 'multicreate: created rel detected by has_relationship_loaded';
  ok !$cd_with_tracks->tracks->first->has_relationship_loaded('cd'), 'multicreate: nested not created rel detected by has_relationship_loaded';
}

done_testing;

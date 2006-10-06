use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 8;

my $artist = $schema->resultset('Artist')->find(1);

# Check that you can leave off the alias
{
  my $existing_cd = $artist->search_related('cds', undef, { prefetch => 'tracks' })->find_or_create({
    title => 'Ted',
    year  => 2006,
  });
  ok(! $existing_cd->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($existing_cd->title, 'Ted', 'find_or_create on prefetched has_many with same column names: name matches existing entry');

  my $new_cd = $artist->search_related('cds', undef, { prefetch => 'tracks' })->find_or_create({
    title => 'Something Else',
    year  => 2006,
  });
  ok(! $new_cd->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($new_cd->title, 'Something Else', 'find_or_create on prefetched has_many with same column names: title matches');
}

# Check that you can specify the alias
{
  my $existing_cd = $artist->search_related('cds', undef, { prefetch => 'tracks' })->find_or_create({
    'me.title' => 'Something Else',
    'me.year'  => 2006,
  });
  ok(! $existing_cd->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($existing_cd->title, 'Something Else', 'find_or_create on prefetched has_many with same column names: can be disambiguated with "me." for existing entry');

  my $new_cd = $artist->search_related('cds', undef, { prefetch => 'tracks' })->find_or_create({
    'me.title' => 'Some New Guy',
    'me.year'  => 2006,
  });
  ok(! $new_cd->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($new_cd->title, 'Some New Guy', 'find_or_create on prefetched has_many with same column names: can be disambiguated with "me." for new entry');
}

use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 8;

my $label = $schema->resultset('Label')->find({ labelid => 1 });

# Check that you can leave off the alias
{
  my $existing_agent = $label->agents->find_or_create({
    name => 'Ted',
  });
  ok(! $existing_agent->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($existing_agent->name, 'Ted', 'find_or_create on prefetched has_many with same column names: name matches existing entry');

  my $new_agent = $label->agents->find_or_create({
    name => 'Someone Else',
  });
  ok(! $new_agent->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($new_agent->name, 'Someone Else', 'find_or_create on prefetched has_many with same column names: name matches');
}

# Check that you can specify the alias
{
  my $existing_agent = $label->agents->find_or_create({
    'me.name' => 'Someone Else',
  });
  ok(! $existing_agent->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($existing_agent->name, 'Someone Else', 'find_or_create on prefetched has_many with same column names: can be disambiguated with "me." for existing entry');

  my $new_agent = $label->agents->find_or_create({
    'me.name' => 'Some New Guy',
  });
  ok(! $new_agent->is_changed, 'find_or_create on prefetched has_many with same column names: row is clean');
  is($new_agent->name, 'Some New Guy', 'find_or_create on prefetched has_many with same column names: can be disambiguated with "me." for new entry');
}

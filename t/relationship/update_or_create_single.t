use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $artist = $schema->resultset ('Artist')->first;

my $genre = $schema->resultset ('Genre')
            ->create ({ name => 'par excellence' });

is ($genre->search_related( 'model_cd' )->count, 0, 'No cds yet');

# expect a create
$genre->update_or_create_related ('model_cd', {
  artist => $artist,
  year => 2009,
  title => 'the best thing since sliced bread',
});

# verify cd was inserted ok
is ($genre->search_related( 'model_cd' )->count, 1, 'One cd');
my $cd = $genre->find_related ('model_cd', {});
is_deeply (
  { map { $_, $cd->get_column ($_) } qw/artist year title/ },
  {
    artist => $artist->id,
    year => 2009,
    title => 'the best thing since sliced bread',
  },
  'CD created correctly',
);

# expect a year update on the only related row
# (non-qunique column + unique column as disambiguator)
$genre->update_or_create_related ('model_cd', {
  year => 2010,
  title => 'the best thing since sliced bread',
});

# re-fetch the cd, verify update
is ($genre->search_related( 'model_cd' )->count, 1, 'Still one cd');
$cd = $genre->find_related ('model_cd', {});
is_deeply (
  { map { $_, $cd->get_column ($_) } qw/artist year title/ },
  {
    artist => $artist->id,
    year => 2010,
    title => 'the best thing since sliced bread',
  },
  'CD year column updated correctly',
);


# expect an update of the only related row
# (update a unique column)
$genre->update_or_create_related ('model_cd', {
  title => 'the best thing since vertical toasters',
});

# re-fetch the cd, verify update
is ($genre->search_related( 'model_cd' )->count, 1, 'Still one cd');
$cd = $genre->find_related ('model_cd', {});
is_deeply (
  { map { $_, $cd->get_column ($_) } qw/artist year title/ },
  {
    artist => $artist->id,
    year => 2010,
    title => 'the best thing since vertical toasters',
  },
  'CD title column updated correctly',
);


# expect a year update on the only related row
# (non-unique column only)
$genre->update_or_create_related ('model_cd', {
  year => 2011,
});

# re-fetch the cd, verify update
is ($genre->search_related( 'model_cd' )->count, 1, 'Still one cd');
$cd = $genre->find_related ('model_cd', {});
is_deeply (
  { map { $_, $cd->get_column ($_) } qw/artist year title/ },
  {
    artist => $artist->id,
    year => 2011,
    title => 'the best thing since vertical toasters',
  },
  'CD year column updated correctly without a disambiguator',
);

# Test multi-level find-or-create functionality.
# We should be able to find-or-create this twice, with the second time
# returning the same item and genre as the first..
my $genre_name = 'Highlander';
my %cd_details = (
    year => '2010',
    title => 'Tasty Treats',
    genre => { name => $genre_name }
);
my $genre2 = $schema->resultset ('Genre')
            ->create ({ name => $genre_name });

my $found1 = $artist->find_or_create_related('cds', { %cd_details });
ok($found1->id, "Found (actually created) album in first iteration");
is($found1->genre->name, $genre_name, ".. with correct genre");

my $found2 = $artist->find_or_create_related('cds', { %cd_details });
ok($found2->id, "Found album in second iteration");
is($found2->id, $found1->id, "..and the IDs are the same.");
is($found2->genre->name, $genre_name, ".. with correct genre");

# Now we repeat the tests, using a sub-level query on one of the critical
# keys that could be used in the "find" part.
my $artist_name = 'Peanut and Cashew Mix';
my %new_cd = (
    year => '2011',
    title => 'Various Failures',
    artist => { name => $artist_name },
);
my $found3 = $genre2->find_or_create_related('cds', { %new_cd });
ok($found3->id, "Found (actually created) album in first iteration");
is($found3->artist->name, $artist_name, "..with correct artist name");

my $found4 = $genre2->find_or_create_related('cds', { %new_cd });
ok($found4->id, "Found album in second iteration");
is($found4->id, $found3->id, "..and the IDs are the same.");
is($found4->artist->name, $artist_name, ".. with correct artist name");
is($found4->artist->id, $found3->artist->id, "..matching artist ids");

done_testing;

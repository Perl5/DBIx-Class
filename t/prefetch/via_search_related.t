use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

lives_ok ( sub {
  my $no_prefetch = $schema->resultset('Track')->search_related(cd =>
    {
      'cd.year' => "2000",
    },
    {
      join => 'tags',
      order_by => 'me.trackid',
      rows => 1,
    }
  );

  my $use_prefetch = $no_prefetch->search(
    {},
    {
      prefetch => 'tags',
    }
  );

  is($use_prefetch->count, $no_prefetch->count, 'counts with and without prefetch match');
  is(
    scalar ($use_prefetch->all),
    scalar ($no_prefetch->all),
    "Amount of returned rows is right"
  );

}, 'search_related prefetch with order_by works');

lives_ok ( sub {
  my $no_prefetch = $schema->resultset('Track')->search_related(cd =>
    {
      'cd.year' => "2000",
      'tagid' => 1,
    },
    {
      join => 'tags',
      rows => 1,
    }
  );

  my $use_prefetch = $no_prefetch->search(
    undef,
    {
      prefetch => 'tags',
    }
  );

  is(
    scalar ($use_prefetch->all),
    scalar ($no_prefetch->all),
    "Amount of returned rows is right"
  );
  is($use_prefetch->count, $no_prefetch->count, 'counts with and without prefetch match');

}, 'search_related prefetch with condition referencing unqualified column of a joined table works');

# make sure chains off prefetched results still work
{
  my $cd = $schema->resultset('CD')->search({}, { prefetch => 'cd_to_producer' })->find(1);

  $schema->is_executed_querycount( sub {
      is( $cd->cd_to_producer->count, 3 ,'Count of prefetched m2m links via accessor' );
    is( scalar $cd->cd_to_producer->all, 3, 'Amount of prefetched m2m link objects via accessor' );
    is( $cd->search_related('cd_to_producer')->count, 3, 'Count of prefetched m2m links via search_related' );
    is( scalar $cd->search_related('cd_to_producer')->all, 3, 'Amount of prefetched m2m links via search_related' );
  }, 0, 'No queries ran so far');

  is( scalar $cd->cd_to_producer->search_related('producer')->all, 3,
      'Amount of objects via search_related off prefetched linker' );
  is( $cd->cd_to_producer->search_related('producer')->count, 3,
      'Count via search_related off prefetched linker' );
  is( scalar $cd->search_related('cd_to_producer')->search_related('producer')->all, 3,
      'Amount of objects via chained search_related off prefetched linker' );
  is( $cd->search_related('cd_to_producer')->search_related('producer')->count, 3,
      'Count via chained search_related off prefetched linker' );
  is( scalar $cd->producers->all, 3,
      'Amount of objects via m2m accessor' );
  is( $cd->producers->count, 3,
      'Count via m2m accessor' );

  $schema->is_executed_querycount( sub {
    is( $cd->cd_to_producer->count, 3 ,'Review count of prefetched m2m links via accessor' );
    is( scalar $cd->cd_to_producer->all, 3, 'Review amount of prefetched m2m link objects via accessor' );
    is( $cd->search_related('cd_to_producer')->count, 3, 'Review count of prefetched m2m links via search_related' );
    is( scalar $cd->search_related('cd_to_producer')->all, 3, 'Rreview amount of prefetched m2m links via search_related' );
  }, 0, 'Still no queries on prefetched linker');
}

# tests with distinct => 1
lives_ok (sub {
    my $rs = $schema->resultset("Artwork")->search(undef, {distinct => 1})
              ->search_related('artwork_to_artist')->search_related('artist',
                undef,
                { prefetch => 'cds' },
              );
    is($rs->all, 0, 'prefetch without WHERE (objects)');
    is($rs->count, 0, 'prefetch without WHERE (count)');

    $rs = $schema->resultset("Artwork")->search(undef, {distinct => 1})
              ->search_related('artwork_to_artist')->search_related('artist',
                { 'cds.title' => 'foo' },
                { prefetch => 'cds' },
              );
    is($rs->all, 0, 'prefetch with WHERE (objects)');
    is($rs->count, 0, 'prefetch with WHERE (count)');


# test where conditions at the root of the related chain
    my $artist_rs = $schema->resultset("Artist")->search({artistid => 2});
    my $artist = $artist_rs->next;
    $artist->create_related ('cds', $_) for (
      {
        year => 1999, title => 'vague cd', genre => { name => 'vague genre' }
      },
      {
        year => 1999, title => 'vague cd2', genre => { name => 'vague genre' }
      },
    );

    $rs = $artist_rs->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'vague genre' },
                    { prefetch => 'cds' },
                 );
    is($rs->all, 1, 'base without distinct (objects)');
    is($rs->count, 1, 'base without distinct (count)');
    # artist -> 2 cds -> 2 genres -> 2 cds for each genre = 4
    is($rs->search_related('cds')->all, 4, 'prefetch without distinct (objects)');
    is($rs->search_related('cds')->count, 4, 'prefetch without distinct (count)');


    $rs = $artist_rs->search_related('cds', {}, { distinct => 1})->search_related('genre',
                    { 'genre.name' => 'vague genre' },
                 );
    is($rs->all, 2, 'distinct does not propagate over search_related (objects)');
    is($rs->count, 2, 'distinct does not propagate over search_related (count)');

    $rs = $rs->search ({}, { distinct => 1} );
    is($rs->all, 1, 'distinct without prefetch (objects)');
    is($rs->count, 1, 'distinct without prefetch (count)');


    $rs = $artist_rs->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'vague genre' },
                    { prefetch => 'cds', distinct => 1 },
                 );
    is($rs->all, 1, 'distinct with prefetch (objects)');
    is($rs->count, 1, 'distinct with prefetch (count)');

    local $TODO = "This makes another 2 trips to the database, it can't be right";
    $schema->is_executed_querycount( sub {

      # the is() calls are not todoified
      local $TODO;

      # artist -> 2 cds -> 2 genres -> 2 cds for each genre + distinct = 2
      is($rs->search_related('cds')->all, 2, 'prefetched distinct with prefetch (objects)');
      is($rs->search_related('cds')->count, 2, 'prefetched distinct with prefetch (count)');

    }, 0, 'No extra queries fired (prefetch survives search_related)');

}, 'distinct generally works with prefetch on deep search_related chains');

# pathological "user knows what they're doing" case
# lifted from production somewhere
{
  $schema->resultset('CD')
   ->search({ cdid => [1,2] })
    ->search_related('tracks', { position => [3,1] })
     ->delete_all;

  my $rs = $schema->resultset('CD')->search_related('tracks', {}, {
    group_by => 'me.title',
    columns => { title => 'me.title', max_trk => \ 'MAX(tracks.position)' },
  });

  is_deeply(
    $rs->search({}, { order_by => 'me.title' })->all_hri,
    [
      { title => "Caterwaulin' Blues", max_trk => 3 },
      { title => "Come Be Depressed With Us", max_trk => 3 },
      { title => "Forkful of bees", max_trk => 1 },
      { title => "Generic Manufactured Singles", max_trk => 3 },
      { title => "Spoonful of bees", max_trk => 1 },
    ],
    'Expected nonsense',
  );
}

done_testing;

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
    my $artist_rs = $schema->resultset("Artist")->search({artistid => 11});


    $rs = $artist_rs->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'foo' },
                    { prefetch => 'cds' },
                 );
    is($rs->all, 0, 'prefetch without distinct (objects)');
    is($rs->count, 0, 'prefetch without distinct (count)');



    $rs = $artist_rs->search(undef, {distinct => 1})
                ->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'foo' },
                 );
    is($rs->all, 0, 'distinct without prefetch (objects)');
    is($rs->count, 0, 'distinct without prefetch (count)');



    $rs = $artist_rs->search({}, {distinct => 1})
                ->search_related('cds')->search_related('genre',
                    { 'genre.name' => 'foo' },
                    { prefetch => 'cds' },
                 );
    is($rs->all, 0, 'distinct with prefetch (objects)');
    is($rs->count, 0, 'distinct with prefetch (count)');



}, 'distinct generally works with prefetch on deep search_related chains');

done_testing;

use strict;
use warnings;

use Test::More;
use Test::Deep;
use Test::Exception;
use lib qw(t/lib);
use DBICTest ':DiffSQL';

my $schema = DBICTest->init_schema();

lives_ok(sub {
  # while cds.* will be selected anyway (prefetch implies it)
  # only the requested me.name column will be fetched.

  # reference sql with select => [...]
  #   SELECT me.name, cds.title, cds.cdid, cds.artist, cds.title, cds.year, cds.genreid, cds.single_track FROM ...

  my $rs = $schema->resultset('Artist')->search(
    { 'cds.title' => { '!=', 'Generic Manufactured Singles' } },
    {
      prefetch => [ qw/ cds / ],
      order_by => [ { -desc => 'me.name' }, 'cds.title' ],
      select => [qw/ me.name cds.title / ],
    },
  );

  is ($rs->count, 2, 'Correct number of collapsed artists');
  my ($we_are_goth) = $rs->all;
  is ($we_are_goth->name, 'We Are Goth', 'Correct first artist');
  is ($we_are_goth->cds->count, 1, 'Correct number of CDs for first artist');
  is ($we_are_goth->cds->first->title, 'Come Be Depressed With Us', 'Correct cd for artist');
}, 'explicit prefetch on a keyless object works');

lives_ok ( sub {

  my $rs = $schema->resultset('CD')->search(
    {},
    {
      order_by => [ { -desc => 'me.year' } ],
    }
  );
  my $years = [qw/ 2001 2001 1999 1998 1997/];

  cmp_deeply (
    [ $rs->search->get_column('me.year')->all ],
    $years,
    'Expected years (at least one duplicate)',
  );

  my @cds_and_tracks;
  for my $cd ($rs->all) {
    my $data = { year => $cd->year, cdid => $cd->cdid };
    for my $tr ($cd->tracks->all) {
      push @{$data->{tracks}}, { $tr->get_columns };
    }
    @{$data->{tracks}} = sort { $a->{trackid} <=> $b->{trackid} } @{$data->{tracks}};
    push @cds_and_tracks, $data;
  }

  my $pref_rs = $rs->search ({}, { columns => [qw/year cdid/], prefetch => 'tracks' });

  my @pref_cds_and_tracks;
  for my $cd ($pref_rs->all) {
    my $data = { $cd->get_columns };
    for my $tr ($cd->tracks->all) {
      push @{$data->{tracks}}, { $tr->get_columns };
    }
    @{$data->{tracks}} = sort { $a->{trackid} <=> $b->{trackid} } @{$data->{tracks}};
    push @pref_cds_and_tracks, $data;
  }

  cmp_deeply (
    \@pref_cds_and_tracks,
    \@cds_and_tracks,
    'Correct collapsing on non-unique primary object'
  );

  cmp_deeply (
    $pref_rs->search ({}, { order_by => [ { -desc => 'me.year' }, 'trackid' ] })->all_hri,
    \@cds_and_tracks,
    'Correct HRI collapsing on non-unique primary object'
  );

}, 'weird collapse lives');


lives_ok(sub {
  # test implicit prefetch as well

  my $rs = $schema->resultset('CD')->search(
    { title => 'Generic Manufactured Singles' },
    {
      join=> 'artist',
      select => [qw/ me.title artist.name / ],
    }
  );

  my $cd = $rs->next;
  is ($cd->title, 'Generic Manufactured Singles', 'CD title prefetched correctly');
  isa_ok ($cd->artist, 'DBICTest::Artist');
  is ($cd->artist->name, 'Random Boy Band', 'Artist object has correct name');

}, 'implicit keyless prefetch works');

# sane error
throws_ok(
  sub {
    $schema->resultset('Track')->search({}, { join => { cd => 'artist' }, '+columns' => 'artist.name' } )->next;
  },
  qr|\QInflation into non-existent relationship 'artist' of 'Track' requested, check the inflation specification (columns/as) ending in '...artist.name'|,
  'Sensible error message on mis-specified "as"',
);

# check complex limiting prefetch without the join-able columns
{
  my $pref_rs = $schema->resultset('Owners')->search({}, {
    rows => 3,
    offset => 1,
    order_by => 'name',
    columns => 'name',  # only the owner name, still prefetch all the books
    prefetch => 'books',
  });

  is_same_sql_bind(
    $pref_rs->as_query,
    '(
      SELECT me.name, books.id, books.source, books.owner, books.title, books.price
        FROM (
          SELECT me.name, me.id
            FROM owners me
          ORDER BY name
          LIMIT ?
          OFFSET ?
        ) me
        LEFT JOIN books books
          ON books.owner = me.id
      ORDER BY name
    )',
    [ [ { sqlt_datatype => "integer" } => 3 ], [ { sqlt_datatype => "integer" } => 1 ] ],
    'Expected SQL on complex limited prefetch with non-selected join condition',
  );

  is_deeply (
    $pref_rs->all_hri,
    [ {
      name => "Waltham",
      books => [ {
        id => 3,
        owner => 2,
        price => 65,
        source => "Library",
        title => "Best Recipe Cookbook",
      } ],
    } ],
    'Expected result on complex limited prefetch with non-selected join condition'
  );

  my $empty_ordered_pref_rs = $pref_rs->search({}, {
    columns => [],  # nothing, we only prefetch the book data
    order_by => 'me.name',
  });
  my $empty_ordered_pref_hri = [ {
    books => [ {
      id => 3,
      owner => 2,
      price => 65,
      source => "Library",
      title => "Best Recipe Cookbook",
    } ],
  } ];

  is_same_sql_bind(
    $empty_ordered_pref_rs->as_query,
    '(
      SELECT books.id, books.source, books.owner, books.title, books.price
        FROM (
          SELECT me.id, me.name
            FROM owners me
          ORDER BY me.name
          LIMIT ?
          OFFSET ?
        ) me
        LEFT JOIN books books
          ON books.owner = me.id
      ORDER BY me.name
    )',
    [ [ { sqlt_datatype => "integer" } => 3 ], [ { sqlt_datatype => "integer" } => 1 ] ],
    'Expected SQL on *ordered* complex limited prefetch with non-selected root data',
  );

  is_deeply (
    $empty_ordered_pref_rs->all_hri,
    $empty_ordered_pref_hri,
    'Expected result on *ordered* complex limited prefetch with non-selected root data'
  );

  $empty_ordered_pref_rs = $empty_ordered_pref_rs->search({}, {
    order_by => [ \ 'LENGTH(me.name)', \ 'RANDOM()' ],
  });

  is_same_sql_bind(
    $empty_ordered_pref_rs->as_query,
    '(
      SELECT books.id, books.source, books.owner, books.title, books.price
        FROM (
          SELECT me.id, me.name
            FROM owners me
          ORDER BY LENGTH(me.name), RANDOM()
          LIMIT ?
          OFFSET ?
        ) me
        LEFT JOIN books books
          ON books.owner = me.id
      ORDER BY LENGTH(me.name), RANDOM()
    )',
    [ [ { sqlt_datatype => "integer" } => 3 ], [ { sqlt_datatype => "integer" } => 1 ] ],
    'Expected SQL on *function-ordered* complex limited prefetch with non-selected root data',
  );

  is_deeply (
    $empty_ordered_pref_rs->all_hri,
    $empty_ordered_pref_hri,
    'Expected result on *function-ordered* complex limited prefetch with non-selected root data'
  );
}


done_testing;

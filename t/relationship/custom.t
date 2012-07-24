use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

$schema->resultset('Artist')->delete;
$schema->resultset('CD')->delete;

my $artist  = $schema->resultset("Artist")->create({ artistid => 21, name => 'Michael Jackson', rank => 20 });
my $artist2 = $schema->resultset("Artist")->create({ artistid => 22, name => 'Chico Buarque', rank => 1 }) ;
my $artist3 = $schema->resultset("Artist")->create({ artistid => 23, name => 'Ziraldo', rank => 1 });
my $artist4 = $schema->resultset("Artist")->create({ artistid => 24, name => 'Paulo Caruso', rank => 20 });

my @artworks;

foreach my $year (1975..1985) {
  my $cd = $artist->create_related('cds', { year => $year, title => 'Compilation from ' . $year });
  push @artworks, $cd->create_related('artwork', {});
}

foreach my $year (1975..1995) {
  my $cd = $artist2->create_related('cds', { year => $year, title => 'Compilation from ' . $year });
  push @artworks, $cd->create_related('artwork', {});
}

foreach my $artwork (@artworks) {
  $artwork->create_related('artwork_to_artist', { artist => $_ }) for ($artist3, $artist4);
}


my $cds_80s_rs = $artist->cds_80s;
is_same_sql_bind(
  $cds_80s_rs->as_query,
  '(
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
      FROM cd me
    WHERE ( ( me.artist = ? AND ( me.year < ? AND me.year > ? ) ) )
  )',
  [
    [
      { sqlt_datatype => 'integer', dbic_colname => 'me.artist' }
        => 21
    ],
    [
      { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.year' }
        => 1990
    ],
    [
      { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.year' }
        => 1979
    ],
  ],
);
my @cds_80s = $cds_80s_rs->all;
is(@cds_80s, 6, '6 80s cds found (1980 - 1985)');
map { ok($_->year < 1990 && $_->year > 1979) } @cds_80s;


my $cds_90s_rs = $artist2->cds_90s;
is_same_sql_bind(
  $cds_90s_rs->as_query,
  '(
    SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
      FROM artist artist__row
      JOIN cd me
        ON ( me.artist = artist__row.artistid AND ( me.year < ? AND me.year > ? ) )
      WHERE ( artist__row.artistid = ? )
  )',
  [
    [
      { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.year' }
        => 2000
    ],
    [
      { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.year' }
        => 1989
    ],
    [ { sqlt_datatype => 'integer', dbic_colname => 'artist__row.artistid' }
        => 22
    ],
  ]
);

# re-test with ::-containing moniker name
# (we don't have any currently, so fudge it with lots of local() )
{
  local $schema->source('Artist')->{source_name} = 'Ar::Tist';
  local $artist2->{related_resultsets};

  is_same_sql_bind(
    $artist2->cds_90s->as_query,
    '(
      SELECT me.cdid, me.artist, me.title, me.year, me.genreid, me.single_track
        FROM artist ar_tist__row
        JOIN cd me
          ON ( me.artist = ar_tist__row.artistid AND ( me.year < ? AND me.year > ? ) )
        WHERE ( ar_tist__row.artistid = ? )
    )',
    [
      [
        { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.year' }
          => 2000
      ],
      [
      { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'me.year' }
          => 1989
      ],
      [ { sqlt_datatype => 'integer', dbic_colname => 'ar_tist__row.artistid' }
          => 22
      ],
    ]
  );
}


my @cds_90s = $cds_90s_rs->all;
is(@cds_90s, 6, '6 90s cds found (1990 - 1995) even with non-optimized search');
map { ok($_->year < 2000 && $_->year > 1989) } @cds_90s;

lives_ok {
  my @cds_90s_95 = $artist2->cds_90s->search({ 'me.year' => 1995 });
  is(@cds_90s_95, 1, '1 90s (95) cds found even with non-optimized search');
  map { ok($_->year == 1995) } @cds_90s_95;
} 'should preserve chain-head "me" alias (API-consistency)';

# search for all artists prefetching published cds in the 80s...
my @all_artists_with_80_cds = $schema->resultset("Artist")->search
  ({ 'cds_80s.cdid' => { '!=' => undef } }, { join => 'cds_80s', distinct => 1 });

is_deeply(
  [ sort ( map { $_->year } map { $_->cds_80s->all } @all_artists_with_80_cds ) ],
  [ sort (1980..1989, 1980..1985) ],
  '16 correct cds found'
);

TODO: {
local $TODO = 'Prefetch on custom rels can not work until the collapse rewrite is finished '
  . '(currently collapser requires a right-side (which is indeterministic) order-by)';
lives_ok {

my @all_artists_with_80_cds_pref = $schema->resultset("Artist")->search
  ({ 'cds_80s.cdid' => { '!=' => undef } }, { prefetch => 'cds_80s' });

is_deeply(
  [ sort ( map { $_->year } map { $_->cds_80s->all } @all_artists_with_80_cds_pref ) ],
  [ sort (1980..1989, 1980..1985) ],
  '16 correct cds found'
);

} 'prefetchy-fetchy-fetch';
} # end of TODO


# try to create_related a 80s cd
throws_ok {
  $artist->create_related('cds_80s', { title => 'related creation 1' });
} qr/\QCustom relationship 'cds_80s' not definitive - returns conditions instead of values for column(s): 'year'/,
'Create failed - complex cond';

# now supply an explicit arg overwriting the ambiguous cond
my $id_2020 = $artist->create_related('cds_80s', { title => 'related creation 2', year => '2020' })->id;
is(
  $schema->resultset('CD')->find($id_2020)->title,
  'related creation 2',
  '2020 CD created correctly'
);

# try a default year from a specific rel
my $id_1984 = $artist->create_related('cds_84', { title => 'related creation 3' })->id;
is(
  $schema->resultset('CD')->find($id_1984)->title,
  'related creation 3',
  '1984 CD created correctly'
);

# try a specific everything via a non-simplified rel
throws_ok {
  $artist->create_related('cds_90s', { title => 'related_creation 4', year => '2038' });
} qr/\QCustom relationship 'cds_90s' does not resolve to a join-free condition fragment/,
'Create failed - non-simplified rel';

# Do a self-join last-entry search
my @last_tracks;
for my $cd ($schema->resultset('CD')->search ({}, { order_by => 'cdid'})->all) {
  push @last_tracks, $cd->tracks
                         ->search ({}, { order_by => { -desc => 'position'} })
                          ->next || ();
}

my $last_tracks_rs = $schema->resultset('Track')->search (
  {'next_tracks.trackid' => undef},
  { join => 'next_tracks', order_by => 'me.cd' },
);

is_deeply (
  [$last_tracks_rs->get_column ('trackid')->all],
  [ map { $_->trackid } @last_tracks ],
  'last group-entry via self-join works',
);

is_deeply (
  [map { $_->last_track->id } grep { $_->last_track } $schema->resultset('CD')->search ({}, { order_by => 'cdid', prefetch => 'last_track'})->all],
  [ map { $_->trackid } @last_tracks ],
  'last_track via insane subquery condition works',
);

is_deeply (
  [map { $_->last_track->id } grep { $_->last_track } $schema->resultset('CD')->search ({}, { order_by => 'cdid'})->all],
  [ map { $_->trackid } @last_tracks ],
  'last_track via insane subquery condition works, even without prefetch',
);

my $artwork = $schema->resultset('Artwork')->search({},{ order_by => 'cd_id' })->first;
my @artists = $artwork->artists->all;
is(scalar @artists, 2, 'the two artists are associated');

my @artwork_artists = $artwork->artwork_to_artist->all;
foreach (@artwork_artists) {
  lives_ok {
    my $artista = $_->artist;
    my $artistb = $_->artist_test_m2m;
    ok($artista->rank < 10 ? $artistb : 1, 'belongs_to with custom rel works.');
    my $artistc = $_->artist_test_m2m_noopt;
    ok($artista->rank < 10 ? $artistc : 1, 'belongs_to with custom rel works even in non-simplified.');
  } 'belongs_to works with custom rels';
}

@artists = ();
lives_ok {
  @artists = $artwork->artists_test_m2m2->all;
} 'manytomany with extended rels in the has many works';
is(scalar @artists, 2, 'two artists');

@artists = ();
lives_ok {
  @artists = $artwork->artists_test_m2m->all;
} 'can fetch many to many with optimized version';
is(scalar @artists, 1, 'only one artist is associated');

@artists = ();
lives_ok {
  @artists = $artwork->artists_test_m2m_noopt->all;
} 'can fetch many to many with non-optimized version';
is(scalar @artists, 1, 'only one artist is associated');


# Make a single for each last_track
my @singles = map {
  $_->create_related('cd_single', {
    title => $_->title . ' (the single)',
    artist => $artist,
    year => 1999,
  }) } @last_tracks
;

# See if chaining works
is_deeply (
  [ map { $_->title } $last_tracks_rs->search_related('cd_single')->all ],
  [ map { $_->title } @singles ],
  'Retrieved singles in proper order'
);

# See if prefetch works
is_deeply (
  [ map { $_->cd_single->title } $last_tracks_rs->search({}, { prefetch => 'cd_single' })->all ],
  [ map { $_->title } @singles ],
  'Prefetched singles in proper order'
);

done_testing;

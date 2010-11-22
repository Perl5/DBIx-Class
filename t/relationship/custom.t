use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();


my $artist = $schema->resultset("Artist")->create({ name => 'Michael Jackson' });
foreach my $year (1975..1985) {
  $artist->create_related('cds', { year => $year, title => 'Compilation from ' . $year });
}

my $artist2 = $schema->resultset("Artist")->create({ name => 'Chico Buarque' }) ;
foreach my $year (1975..1995) {
  $artist2->create_related('cds', { year => $year, title => 'Compilation from ' . $year });
}

my @cds_80s = $artist->cds_80s;
is(@cds_80s, 6, '6 80s cds found (1980 - 1985)');
map { ok($_->year < 1990 && $_->year > 1979) } @cds_80s;

my @cds_90s = $artist2->cds_90s;
is(@cds_90s, 6, '6 90s cds found (1990 - 1995) even with non-optimized search');
map { ok($_->year < 2000 && $_->year > 1989) } @cds_90s;

# search for all artists prefetching published cds in the 80s...
#####
# the join must be a prefetch, but it can't work until the collapse rewrite is finished
# (right-side vs left-side order)
#####
lives_ok {
  my @all_artists_with_80_cds = $schema->resultset("Artist")->search
    ({ 'cds_80s.cdid' => { '!=' => undef } }, { prefetch => 'cds_80s' })->all;

  is_deeply
    ([ sort ( map { $_->year } map { $_->cds_80s->all } @all_artists_with_80_cds ) ],
     [ sort (1980..1989, 1980..1985) ],
     '16 correct cds found'
    );
} 'prefetchy-fetchy-fetch';

my @all_artists_with_80_cds = $schema->resultset("Artist")->search
  ({ 'cds_80s.cdid' => { '!=' => undef } }, { join => 'cds_80s', distinct => 1 });

is_deeply(
  [ sort ( map { $_->year } map { $_->cds_80s->all } @all_artists_with_80_cds ) ],
  [ sort (1980..1989, 1980..1985) ],
  '16 correct cds found'
);

# try to create_related a 80s cd
throws_ok {
  $artist->create_related('cds_80s', { title => 'related creation 1' });
} qr/\Qunable to set_from_related via complex 'cds_80s' condition on column(s): 'year'/, 'Create failed - complex cond';

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
} qr/\Qunable to set_from_related - no simplified condition available for 'cds_90s'/, 'Create failed - non-simplified rel';

# Do a self-join last-entry search
my @last_track_ids;
for my $cd ($schema->resultset('CD')->search ({}, { order_by => 'cdid'})->all) {
  push @last_track_ids, $cd->tracks
                            ->search ({}, { order_by => { -desc => 'position'} })
                              ->get_column ('trackid')
                                ->next;
}

my $last_tracks = $schema->resultset('Track')->search (
  {'next_track.trackid' => undef},
  { join => 'next_track', order_by => 'me.cd' },
);

is_deeply (
  [$last_tracks->get_column ('trackid')->all],
  [ grep { $_ } @last_track_ids ],
  'last group-entry via self-join works',
);

done_testing;

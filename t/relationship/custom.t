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
is(@cds_80s, 6, '6 80s cds found');

my @cds_90s = $artist2->cds_90s;
is(@cds_90s, 6, '6 90s cds found even with non-optimized search');

map { ok($_->year < 1990 && $_->year > 1979) } @cds_80s;


# search for all artists prefetching published cds in the 80s...
my @all_cds_80s = $schema->resultset("Artist")->search
  ({ 'cds_80s_noopt.cdid' => { '!=' => undef } }, { join => 'cds_80s_noopt' });
is(@all_cds_80s, 16, '16 cds found even with the non-optimized search');

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

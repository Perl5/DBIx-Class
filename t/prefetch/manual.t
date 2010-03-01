use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset ('CD')->search ({}, {
  join => [ 'tracks', { single_track => { cd => { artist => { cds => 'tracks' } } } }  ],
  collapse => 1,
  columns => [
    { 'year'                                    => 'me.year' },               # non-unique
    { 'genreid'                                 => 'me.genreid' },            # nullable
    { 'tracks.title'                            => 'tracks.title' },          # non-unique (no me.id)
    { 'single_track.cd.artist.cds.cdid'         => 'cds.cdid' },              # to give uniquiness to ...tracks.title below
    { 'single_track.cd.artist.cds.artist'       => 'cds.artist' },            # non-unique
    { 'single_track.cd.artist.cds.year'         => 'cds.year' },              # non-unique
    { 'single_track.cd.artist.cds.genreid'      => 'cds.genreid' },           # nullable
    { 'single_track.cd.artist.cds.tracks.title' => 'tracks_2.title' },        # unique when combined with ...cds.cdid above
    { 'latest_cd'                               => { max => 'cds.year' } },   # random function
  ],
  result_class => 'DBIx::Class::ResultClass::HashRefInflator',
});

use Data::Dumper::Concise;
die Dumper [$rs->all];



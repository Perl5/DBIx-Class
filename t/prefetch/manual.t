use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema(no_populate => 1);

$schema->resultset('CD')->create({
  title => 'Equinoxe',
  year => 1978,
  artist => { name => 'JMJ' },
  genre => { name => 'electro' },
  tracks => [
    { title => 'e1' },
    { title => 'e2' },
    { title => 'e3' },
  ],
  single_track => {
    title => 'o1',
    cd => {
      title => 'Oxygene',
      year => 1976,
      artist => {
        name => 'JMJ',
        cds => [
          {
            title => 'Magnetic Fields',
            year => 1981,
            genre => { name => 'electro' },
            tracks => [
              { title => 'm1' },
              { title => 'm2' },
              { title => 'm3' },
              { title => 'm4' },
            ],
          },
        ],
      },
      tracks => [
        { title => 'o2', position => 2},  # the position should not be here, bug in MC
      ],
    },
  },
});

my $rs = $schema->resultset ('CD')->search ({}, {
  join => [ 'tracks', { single_track => { cd => { artist => { cds => 'tracks' } } } }  ],
  collapse => 1,
  columns => [
    { 'year'                                    => 'me.year' },               # non-unique
    { 'genreid'                                 => 'me.genreid' },            # nullable
    { 'tracks.title'                            => 'tracks.title' },          # non-unique (no me.id)
    { 'single_track.cd.artist.cds.cdid'         => 'cds.cdid' },              # to give uniquiness to ...tracks.title below
    { 'single_track.cd.artist.artistid'         => 'artist.artistid' },       # uniqufies entire parental chain
    { 'single_track.cd.artist.cds.year'         => 'cds.year' },              # non-unique
    { 'single_track.cd.artist.cds.genreid'      => 'cds.genreid' },           # nullable
    { 'single_track.cd.artist.cds.tracks.title' => 'tracks_2.title' },        # unique when combined with ...cds.cdid above
    { 'latest_cd'                     => \ "(SELECT MAX(year) FROM cd)" },    # random function
    { 'title'                                   => 'me.title' },              # uniquiness for me
    { 'artist'                                  => 'me.artist' },             # uniquiness for me
  ],
  order_by => [{ -desc => 'cds.year' }, { -desc => 'me.title'} ],
});

my $hri_rs = $rs->search({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' });

is_deeply (
  [$hri_rs->all],
  [
    {
      artist => 1,
      genreid => 1,
      latest_cd => 1981,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => [
              {
                cdid => 1,
                genreid => 1,
                tracks => [
                  {
                    title => "m1"
                  },
                  {
                    title => "m2"
                  },
                  {
                    title => "m3"
                  },
                  {
                    title => "m4"
                  }
                ],
                year => 1981
              },
              {
                cdid => 3,
                genreid => 1,
                tracks => [
                  {
                    title => "e1"
                  },
                  {
                    title => "e2"
                  },
                  {
                    title => "e3"
                  }
                ],
                year => 1978
              },
              {
                cdid => 2,
                genreid => undef,
                tracks => [
                  {
                    title => "o1"
                  },
                  {
                    title => "o2"
                  }
                ],
                year => 1976
              }
            ]
          }
        }
      },
      title => "Equinoxe",
      tracks => [
        {
          title => "e1"
        },
        {
          title => "e2"
        },
        {
          title => "e3"
        }
      ],
      year => 1978
    },
    {
      artist => 1,
      genreid => undef,
      latest_cd => 1981,
      single_track => undef,
      title => "Oxygene",
      tracks => [
        {
          title => "o1"
        },
        {
          title => "o2"
        }
      ],
      year => 1976
    },
    {
      artist => 1,
      genreid => 1,
      latest_cd => 1981,
      single_track => undef,
      title => "Magnetic Fields",
      tracks => [
        {
          title => "m1"
        },
        {
          title => "m2"
        },
        {
          title => "m3"
        },
        {
          title => "m4"
        }
      ],
      year => 1981
    },
  ],
  'W00T, manual prefetch with collapse works'
);

my $row = $rs->next;

TODO: {
  local $TODO = 'Something is wrong with filter type rels, they throw on incomplete objects >.<';

  lives_ok {
    is_deeply (
      { $row->single_track->get_columns },
      {},
      'empty intermediate object ok',
    )
  } 'no exception';
}

is ($rs->cursor->next, undef, 'cursor exhausted');

done_testing;

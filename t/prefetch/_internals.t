use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use B::Deparse;


my $schema = DBICTest->init_schema(no_deploy => 1);

my ($as, $vals, @pairs);

# artwork-artist deliberately mixed around
@pairs = (
  'artwork_to_artist.artist_id' => '2',

  'cd_id' => '1',

  'artwork_to_artist.artwork_cd_id' => '1',

  'cd.artist' => '1',
  'cd.cdid' => '1',
  'cd.title' => 'Spoonful of bees',

  'cd.artist.artistid' => '7',
  'cd.artist.name' => 'Caterwauler McCrae',
  'artwork_to_artist.artist.name' => 'xenowhinycide',
);
while (@pairs) {
  push @$as, shift @pairs;
  push @$vals, shift @pairs;
}

=begin

my $parser = $schema->source ('Artwork')->_mk_row_parser({
  inflate_map => $as,
  collapse => 1,
});

is_deeply (
  $parser->($vals),
  [
    {
      cd_id => 1,
    },

    {
      artwork_to_artist => [
        {
          artist_id => 2,
          artwork_cd_id => 1,
        },
        {
          artist => [
            {
              name => 'xenowhinycide',
            },
            undef,
            [ 2, 1 ], # inherited from artwork_to_artist (child-parent definition)
          ],
        },
        [ 2, 1 ]  # artwork_to_artist own data, in selection order
      ],

      cd => [
        {
          artist => 1,
          cdid => 1,
          title => 'Spoonful of bees',
        },
        {
          artist => [
            {
              artistid => 7,
              name => 'Caterwauler McCrae',
            },
            undef,
            [ 7 ], # our own id
          ]
        },
        [ 1 ], # our cdid fk
      ]
    },
    [ 1 ], # our id
  ],
  'generated row parser works as expected',
);

#=begin

undef $_ for ($as, $vals);
@pairs = (
  'name' => 'Caterwauler McCrae',
  'cds.tracks.cd' => '3',
  'cds.tracks.title' => 'Fowlin',
  'cds.tracks.cd_single.title' => 'Awesome single',
);
while (@pairs) {
  push @$as, shift @pairs;
  push @$vals, shift @pairs;
}
$parser = $schema->source ('Artist')->_mk_row_parser($as);

is_deeply (
  $parser->($vals),
  [
    {
      name => 'Caterwauler McCrae'
    },
    {
      cds => [
        {},
        {
          tracks => [
            {
              cd => 3,
              title => 'Fowlin'
            },
            {
              cd_single => [
                {
                  title => 'Awesome single',
                },
              ],
            },
          ]
        }
      ]
    }
  ],
  'generated parser works as expected over missing joins (no collapse)',
);

=cut

undef $_ for ($as, $vals);
@pairs = (
    'tracks.lyrics.lyric_versions.text'                => 'unique when combined with the lyric collapsable by the 1:1 tracks-parent',
    'existing_single_track.cd.artist.artistid'         => 'artist_id (gives uniq. to its entire parent chain)',
    'existing_single_track.cd.artist.cds.year'         => 'non-unique cds col (year)',
    'year'                                             => 'non unique main year',
    'genreid'                                          => 'non-unique/nullable main genid',
    'tracks.title'                                     => 'non-unique title (missing multicol const. part)',
    'existing_single_track.cd.artist.cds.cdid'         => 'cds unique id col to give uniquiness to ...tracks.title below',
    'latest_cd'                                        => 'random function (not a colname)',
    'existing_single_track.cd.artist.cds.tracks.title' => 'unique track title (when combined with ...cds.cdid above)',
    'existing_single_track.cd.artist.cds.genreid'      => 'nullable cds col (genreid)',
);
while (@pairs) {
  push @$as, shift @pairs;
  push @$vals, shift @pairs;
}

is_deeply (
  $schema->source ('CD')->_resolve_collapse ( { map { $as->[$_] => $_ } (0 .. $#$as) } ),
  {
    -node_index => 1,
    -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
    -branch_id => [ 0, 1, 5, 6, 8 ],

    existing_single_track => {
      -node_index => 2,
      -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
      -branch_id => [ 1, 6, 8 ],
      -is_single => 1,

      cd => {
        -node_index => 3,
        -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
        -branch_id => [ 1, 6, 8 ],
        -is_single => 1,

        artist => {
          -node_index => 4,
          -node_id => [ 1 ], # existing_single_track.cd.artist.artistid
          -branch_id => [ 1, 6, 8 ],
          -is_single => 1,

          cds => {
            -node_index => 5,
            -node_id => [ 6 ], # existing_single_track.cd.artist.cds.cdid
            -branch_id => [ 6, 8 ],
            -is_optional => 1,

            tracks => {
              -node_index => 6,
              -node_id => [ 6, 8 ], # existing_single_track.cd.artist.cds.cdid, existing_single_track.cd.artist.cds.tracks.title
              -branch_id => [ 6, 8 ],
              -is_optional => 1,
            }
          }
        }
      }
    },
    tracks => {
      -node_index => 7,
      -node_id => [ 1, 5 ], # existing_single_track.cd.artist.artistid, tracks.title
      -branch_id => [ 0, 1, 5 ],
      -is_optional => 1,

      lyrics => {
        -node_index => 8,
        -node_id => [ 1, 5 ], # existing_single_track.cd.artist.artistid, tracks.title
        -branch_id => [ 0, 1, 5 ],
        -is_single => 1,
        -is_optional => 1,

        lyric_versions => {
          -node_index => 9,
          -node_id => [ 0, 1, 5 ], # tracks.lyrics.lyric_versions.text, existing_single_track.cd.artist.artistid, tracks.title
          -branch_id => [ 0, 1, 5 ],
          -is_optional => 1,
        },
      },
    }
  },
  'Correct collapse map constructed',
);

done_testing;
__END__
=cut

my $parser = $schema->source ('CD')->_mk_row_parser ({ inflate_map => $as, collapse => 1 });

=begin

is_deeply (
  $parser->($vals),
  [
    {
      latest_cd => 'random function (not a colname)',
      year => 'non unique main year',
      genreid => 'non-unique/nullable main genid'
    },
    {
      existing_single_track => [
        {},
        {
          cd => [
            {},
            {
              artist => [
                { artistid => 'artist_id (gives uniq. to its entire parent chain)' },
                {
                  cds => [
                    {
                      cdid => 'cds unique id col to give uniquiness to ...tracks.title below',
                      year => 'non-unique cds col (year)',
                      genreid => 'nullable cds col (genreid)'
                    },
                    {
                      tracks => [
                        {
                          title => 'unique track title (when combined with ...cds.cdid above)'
                        },
                        undef,
                        [
                          'cds unique id col to give uniquiness to ...tracks.title below',
                          'unique track title (when combined with ...cds.cdid above)',
                        ],
                      ]
                    },
                    [ 'cds unique id col to give uniquiness to ...tracks.title below' ],
                  ]
                },
                [ 'artist_id (gives uniq. to its entire parent chain)' ],
              ]
            },
            [ 'artist_id (gives uniq. to its entire parent chain)' ],
          ]
        },
        [ 'artist_id (gives uniq. to its entire parent chain)' ],
      ],
      tracks => [
        {
          title => 'non-unique title (missing multicol const. part)'
        },
        {
          lyrics => [
            {},
            {
              lyric_versions => [
                {
                  text => 'unique when combined with the lyric collapsable by the 1:1 tracks-parent',
                },
                undef,
                [
                  'unique when combined with the lyric collapsable by the 1:1 tracks-parent',
                  'artist_id (gives uniq. to its entire parent chain)',
                  'non-unique title (missing multicol const. part)',
                ],
              ],
            },
            [
              'artist_id (gives uniq. to its entire parent chain)',
              'non-unique title (missing multicol const. part)',
            ],
          ],
        },
        [
          'artist_id (gives uniq. to its entire parent chain)',
          'non-unique title (missing multicol const. part)',
        ],
      ],
    },
    [ 'artist_id (gives uniq. to its entire parent chain)' ],
  ],
  'Proper row parser constructed',
);

=cut

# For extra insanity test/showcase the parser's guts:
my $deparser = B::Deparse->new;
is (
  $deparser->coderef2text ($parser),
  $deparser->coderef2text ( sub { package DBIx::Class::ResultSource;
    my $rows = [];
    while (1) {
      my $r = (shift @{$_[0]->{row_stash}}) || ($_[0]->{next_row} and $_[0]->{next_row}->()) || last;

    }
    return $rows


    [
      {
        genreid => $_[0][4],
        latest_cd => $_[0][7],
        year => $_[0][3]
      },
      {

        existing_single_track => [
          {},
          {
            cd => [
              {},
              {
                artist => [
                  {
                    artistid => $_[0][1]
                  },
                  {

                    !defined($_[0][6]) ? () : (
                    cds => [
                      {
                        cdid => $_[0][6],
                        genreid => $_[0][9],
                        year => $_[0][2]
                      },
                      {

                        !defined($_[0][8]) ? () : (
                        tracks => [
                          {
                            title => $_[0][8]
                          },
                          undef,
                          [ $_[0][6], $_[0][8] ]
                        ])

                      },
                      [ $_[0][6] ]
                    ]),

                  },
                  [ $_[0][1] ],
                ],
              },
              [ $_[0][1] ],
            ],
          },
          [ $_[0][1] ],
        ],

        !defined($_[0][5]) ? () : (
        tracks => [
          {
            title => $_[0][5],
          },
          {

            lyrics => [
              {},
              {

                !defined($_[0][0]) ? () : (
                lyric_versions => [
                  {
                    text => $_[0][0]
                  },
                  undef,
                  [ $_[0][0], $_[0][1], $_[0][5] ],
                ]),

              },
              [ $_[0][1], $_[0][5] ],
            ],

          },
          [ $_[0][1], $_[0][5] ],
        ]),
      },
      [ $_[0][1] ],
    ];
  }),
  'Deparsed version of the parser coderef looks correct',
);

done_testing;

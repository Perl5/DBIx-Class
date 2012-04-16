use strict;
use warnings;

use Test::More;
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
        { title => 'o2', position => 2},  # the position should not be needed here, bug in MC
      ],
    },
  },
});

{
  package DBICTest::_IRCapture;
  sub inflate_result { [@_[2,3]] };
}

is_deeply(
  ([$schema->resultset ('CD')->search ({}, {
    result_class => 'DBICTest::_IRCapture',
    prefetch => { single_track => { cd => 'artist' } },
    order_by => 'me.cdid',
  })->all]),
  [
    [
      { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
      { single_track => [
        { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
        {  cd => [
          { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
          {
            artist => [
              { artistid => undef, name => undef, charfield => undef, rank => undef }
            ]
          }
        ] }
      ] }
    ],
    [
      { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
      { single_track => [
        { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
        {  cd => [
          { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
          {
            artist => [
              { artistid => undef, name => undef, charfield => undef, rank => undef }
            ]
          }
        ] }
      ] }
    ],
    [
      { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
      { single_track => [
        { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef },
        {  cd => [
          { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
          {
            artist => [
              { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 }
            ]
          }
        ] }
      ] }
    ],
  ],
  'Simple 1:1 descend with classic prefetch ok'
);

is_deeply(
  [$schema->resultset ('CD')->search ({}, {
    result_class => 'DBICTest::_IRCapture',
    join => { single_track => { cd => 'artist' } },
    columns => [
      { 'year'                                    => 'me.year' },
      { 'genreid'                                 => 'me.genreid' },
      { 'single_track.cd.artist.artistid'         => 'artist.artistid' },
      { 'title'                                   => 'me.title' },
      { 'artist'                                  => 'me.artist' },
    ],
    order_by => 'me.cdid',
  })->all],
  [
    [
      { artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
      { single_track => [
        undef,
        {  cd => [
          undef,
          {
            artist => [
              { artistid => undef }
            ]
          }
        ] }
      ] }
    ],
    [
      { artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
      { single_track => [
        undef,
        {  cd => [
          undef,
          {
            artist => [
              { artistid => undef }
            ]
          }
        ] }
      ] }
    ],
    [
      { artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
      { single_track => [
        undef,
        {  cd => [
          undef,
          {
            artist => [
              { artistid => 1 }
            ]
          }
        ] }
      ] }
    ],
  ],
  'Simple 1:1 descend with missing selectors ok'
);

is_deeply(
  ([$schema->resultset ('CD')->search ({}, {
    result_class => 'DBICTest::_IRCapture',
    prefetch => [ { single_track => { cd => { artist => { cds => 'tracks' } } } } ],
    order_by => [qw/me.cdid tracks.trackid/],
  })->all]),
  [
    [
      { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
      { single_track => [
        { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
        {  cd => [
          { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
          {
            artist => [
              { artistid => undef, name => undef, charfield => undef, rank => undef },
              { cds => [ [
                { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
                { tracks => [ [
                  { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
                ] ] },
              ]]},
            ],
          },
        ] },
      ] },
    ],
    [
      { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
      { single_track => [
        { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
        {  cd => [
          { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
          {
            artist => [
              { artistid => undef, name => undef, charfield => undef, rank => undef },
              { cds => [ [
                { cdid => undef, single_track => undef, artist => undef, genreid => undef, year => undef, title => undef },
                { tracks => [ [
                  { trackid => undef, title => undef, position => undef, cd => undef, last_updated_at => undef, last_updated_on => undef },
                ] ] },
              ]]},
            ]
          }
        ] }
      ] }
    ],
    [
      { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
      { single_track => [
        { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef },
        {  cd => [
          { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
          {
            artist => [
              { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
              { cds => [
                [
                  { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
                  { tracks => [
                    [ { trackid => 1, title => 'm1', position => 1, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                    [ { trackid => 2, title => 'm2', position => 2, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                    [ { trackid => 3, title => 'm3', position => 3, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                    [ { trackid => 4, title => 'm4', position => 4, cd => 1, last_updated_at => undef, last_updated_on => undef } ],
                  ]},
                ],
                [
                  { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
                  { tracks => [
                    [ { trackid => 5, title => 'o2', position => 2, cd => 2, last_updated_at => undef, last_updated_on => undef } ],
                    [ { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef } ],
                  ]},
                ],
                [
                  { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
                  { tracks => [
                    [ { trackid => 7, title => 'e1', position => 1, cd => 3, last_updated_at => undef, last_updated_on => undef } ],
                    [ { trackid => 8, title => 'e2', position => 2, cd => 3, last_updated_at => undef, last_updated_on => undef } ],
                    [ { trackid => 9, title => 'e3', position => 3, cd => 3, last_updated_at => undef, last_updated_on => undef } ],
                  ]},
                ],
              ]},
            ]
          }
        ] }
      ] }
    ],
  ],
  'Collapsing 1:1 ending in chained has_many with classic prefetch ok'
);

is_deeply (
  ([$schema->resultset ('Artist')->search ({}, {
    result_class => 'DBICTest::_IRCapture',
    join => { cds => 'tracks' },
    '+columns' => [
      (map { "cds.$_" } $schema->source('CD')->columns),
      (map { +{ "cds.tracks.$_" => "tracks.$_" } } $schema->source('Track')->columns),
    ],
    order_by => [qw/cds.cdid tracks.trackid/],
  })->all]),
  [
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { tracks => [
          { trackid => 1, title => 'm1', position => 1, cd => 1, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { tracks => [
          { trackid => 2, title => 'm2', position => 2, cd => 1, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { tracks => [
          { trackid => 3, title => 'm3', position => 3, cd => 1, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 1, single_track => undef, artist => 1, genreid => 1, year => 1981, title => "Magnetic Fields" },
        { tracks => [
          { trackid => 4, title => 'm4', position => 4, cd => 1, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
        { tracks => [
          { trackid => 5, title => 'o2', position => 2, cd => 2, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 2, single_track => undef, artist => 1, genreid => undef, year => 1976, title => "Oxygene" },
        { tracks => [
          { trackid => 6, title => 'o1', position => 1, cd => 2, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
        { tracks => [
          { trackid => 7, title => 'e1', position => 1, cd => 3, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
        { tracks => [
          { trackid => 8, title => 'e2', position => 2, cd => 3, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
    [
      { artistid => 1, name => 'JMJ', charfield => undef, rank => 13 },
      { cds => [
        { cdid => 3, single_track => 6, artist => 1, genreid => 1, year => 1978, title => "Equinoxe" },
        { tracks => [
          { trackid => 9, title => 'e3', position => 3, cd => 3, last_updated_at => undef, last_updated_on => undef },
        ]},
      ]},
    ],
  ],
  'Non-Collapsing chained has_many ok'
);

done_testing;

use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema(no_deploy => 1);


my $irow = $schema->source ('Artwork')->_parse_row (
  {
    'cd_id' => '1',

    'artwork_to_artist.artist_id' => '2',
    'artwork_to_artist.artwork_cd_id' => '1',

    'cd.artist' => '1',
    'cd.cdid' => '1',
    'cd.title' => 'Spoonful of bees',

    'cd.artist.artistid' => '1',
    'cd.artist.name' => 'Caterwauler McCrae',
  },
  'will collapse'
);

is_deeply (
  $irow,
  [
    {
      'cd_id' => '1'
    },
    {
      'artwork_to_artist' => [
        [
          {
            'artist_id' => '2',
            'artwork_cd_id' => '1'
          }
        ]
      ],

      'cd' => [
        {
          'artist' => '1',
          'cdid' => '1',
          'title' => 'Spoonful of bees',
        },
        {
          'artist' => [
            {
              'artistid' => '1',
              'name' => 'Caterwauler McCrae',
            }
          ]
        }
      ]
    }
  ],
  '_parse_row works as expected with expected collapse',
);

$irow = $schema->source ('Artist')->_parse_row (
  {
    'name' => 'Caterwauler McCrae',
    'cds.tracks.cd' => '3',
    'cds.tracks.title' => 'Fowlin',
    'cds.tracks.cd_single.title' => 'Awesome single',
  }
);
is_deeply (
  $irow,
  [
    {
      'name' => 'Caterwauler McCrae'
    },
    {
      'cds' => [
        {},
        {
          'tracks' => [
            {
              'cd' => '3',
              'title' => 'Fowlin'
            },
            {
              'cd_single' => [
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
  '_parse_row works over missing joins without collapse',
);

done_testing;

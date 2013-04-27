use strict;
use warnings;
use Test::More tests => 1;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema( no_connect => 1, no_deploy => 1 );

is_deeply(
  $schema->source_tree(),
  { 'SequenceTest' => {},
    'Lyrics'       => {
      'CD' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Genre' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Track' => [
        { 'cond'          => { 'foreign.trackid' => 'self.track_id' },
          'relation_name' => 'track',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Artist' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 2,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 2,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'Dummy'          => {},
    'CustomSql'      => {},
    'BooksInLibrary' => {
      'Owners' => [
        { 'cond'          => { 'foreign.id' => 'self.owner' },
          'relation_name' => 'owner',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ]
    },
    'LyricVersion' => {
      'Lyrics' => [
        { 'cond'          => { 'foreign.lyric_id' => 'self.lyric_id' },
          'relation_name' => 'lyric',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'CD' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Genre' => [
        { 'distance' => 4,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Track' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 4,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'CD' => {
      'Genre' => [
        { 'cond'          => { 'foreign.genreid' => 'self.genreid' },
          'relation_name' => 'genre_inefficient',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        },
        { 'cond'          => { 'foreign.genreid' => 'self.genreid' },
          'relation_name' => 'genre',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        }
      ],
      'Track' => [
        { 'cond'          => { 'foreign.trackid' => 'self.single_track' },
          'relation_name' => 'single_track',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        },
        { 'cond'          => { 'foreign.trackid' => 'self.single_track' },
          'relation_name' => 'existing_single_track',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        }
      ],
      'Artist' => [
        { 'cond'          => { 'foreign.artistid' => 'self.artist' },
          'relation_name' => 'artist',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        },
        { 'cond' => { 'foreign.artistid' => 'self.artist' },
          'relation_name' => 'very_long_artist_relationship',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 2,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 2,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'Artwork' => {
      'CD' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd_id' },
          'relation_name' => 'cd',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Genre' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Track' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'Track' => {
      'CD' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'cd',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        },
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'disc',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Genre' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'year1999cd',
          'distance'      => 1,
          'type'          => 'View',
          'hard'          => 0
        }
      ],
      'Artist' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year2000CDs' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'year2000cd',
          'distance'      => 1,
          'type'          => 'View',
          'hard'          => 0
        }
      ]
    },
    'Tag' => {
      'CD' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'cd',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Genre' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Track' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'NoPrimaryKey' => {},
    'ForceForeign' => {
      'Artist' => [
        { 'cond'          => { 'foreign.artistid' => 'self.artist' },
          'relation_name' => 'artist_1',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        }
      ]
    },
    'FourKeys'          => {},
    'Artwork_to_Artist' => {
      'CD' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Genre' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Artwork' => [
        { 'cond'          => { 'foreign.cd_id' => 'self.artwork_cd_id' },
          'relation_name' => 'artwork',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Track' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 4,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'cond'          => { 'foreign.artistid' => 'self.artist_id' },
          'relation_name' => 'artist',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        },
        { 'cond'          => 'CODE',
          'relation_name' => 'artist_test_m2m_noopt',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => undef
        },
        { 'cond'          => 'CODE',
          'relation_name' => 'artist_test_m2m',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => undef
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 4,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'Collection'          => {},
    'Producer'            => {},
    'TimestampPrimaryKey' => {},
    'SourceNameArtists'   => {},
    'Employee'            => {
      'Encoded' => [
        { 'cond'          => { 'foreign.id' => 'self.encoded' },
          'relation_name' => 'secretkey',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        }
      ]
    },
    'Serialized'     => {},
    'CD_to_Producer' => {
      'CD' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'cd',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Genre' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Producer' => [
        { 'cond'          => { 'foreign.producerid' => 'self.producer' },
          'relation_name' => 'producer',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Track' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'LinerNotes' => {
      'CD' => [
        { 'cond'          => { 'foreign.cdid' => 'self.liner_id' },
          'relation_name' => 'cd',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Genre' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Track' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'Artist'           => {},
    'CollectionObject' => {
      'TypedObject' => [
        { 'cond'          => { 'foreign.objectid' => 'self.object' },
          'relation_name' => 'object',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Collection' => [
        { 'cond'          => { 'foreign.collectionid' => 'self.collection' },
          'relation_name' => 'collection',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ]
    },
    'FourKeys_to_TwoKeys' => {
      'FourKeys' => [
        {
          'cond' => {
            'foreign.foo'     => 'self.f_foo',
            'foreign.goodbye' => 'self.f_goodbye',
            'foreign.hello'   => 'self.f_hello',
            'foreign.bar'     => 'self.f_bar'
          },
          'relation_name' => 'fourkeys',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'CD' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Genre' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'TwoKeys' => [
        {
          'cond' => {
            'foreign.cd'     => 'self.t_cd',
            'foreign.artist' => 'self.t_artist'
          },
          'relation_name' => 'twokeys',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Track' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 4,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 4,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'TwoKeyTreeLike' => {
      'TwoKeyTreeLike' => [
        {
          'cond' => {
            'foreign.id1' => 'self.parent1',
            'foreign.id2' => 'self.parent2'
          },
          'relation_name' => 'parent',
          'distance'      => 0,
          'type'          => 'Table',
          'hard'          => 1
        }
      ]
    },
    'SelfRefAlias' => {
      'SelfRef' => [
        { 'cond'          => { 'foreign.id' => 'self.self_ref' },
          'relation_name' => 'self_ref',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        },
        { 'cond'          => { 'foreign.id' => 'self.alias' },
          'relation_name' => 'alias',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ]
    },
    'BindType' => {},
    'Owners'   => {},
    'Bookmark' => {
      'Link' => [
        { 'cond'          => { 'foreign.id' => 'self.link' },
          'relation_name' => 'link',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 0
        }
      ]
    },
    'SelfRef'  => {},
    'TreeLike' => {
      'TreeLike' => [
        { 'cond'          => { 'foreign.id' => 'self.parent' },
          'relation_name' => 'parent',
          'distance'      => 0,
          'type'          => 'Table',
          'hard'          => 0
        }
      ]
    },
    'Link'        => {},
    'TypedObject' => {},
    'Money'       => {},
    'Event'       => {},
    'Genre'       => {},
    'TwoKeys'     => {
      'CD' => [
        { 'cond'          => { 'foreign.cdid' => 'self.cd' },
          'relation_name' => 'cd',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Genre' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Track' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'cond'          => { 'foreign.artistid' => 'self.artist' },
          'relation_name' => 'artist',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 3,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'ArtistSubclass' => {},
    'Image'          => {
      'CD' => [
        { 'distance' => 2,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Genre' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Artwork' => [
        { 'cond'          => { 'foreign.cd_id' => 'self.artwork_id' },
          'relation_name' => 'artwork',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ],
      'Track' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 0
        }
      ],
      'Artist' => [
        { 'distance' => 3,
          'type'     => 'Table',
          'hard'     => 1
        }
      ],
      'Year1999CDs' => [
        { 'distance' => 4,
          'type'     => 'View',
          'hard'     => 0
        }
      ],
      'Year2000CDs' => [
        { 'distance' => 4,
          'type'     => 'View',
          'hard'     => 0
        }
      ]
    },
    'Encoded'             => {},
    'EventTZ'             => {},
    'ArtistUndirectedMap' => {
      'Artist' => [
        { 'cond'          => { 'foreign.artistid' => 'self.id1' },
          'relation_name' => 'artist1',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        },
        { 'cond'          => { 'foreign.artistid' => 'self.id2' },
          'relation_name' => 'artist2',
          'distance'      => 1,
          'type'          => 'Table',
          'hard'          => 1
        }
      ]
    },
    'OneKey' => {}
  },
  'got correct source tree'
);


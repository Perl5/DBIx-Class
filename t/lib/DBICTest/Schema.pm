package # hide from PAUSE
    DBICTest::Schema;

use base qw/DBIx::Class::Schema/;

no warnings qw/qw/;

__PACKAGE__->load_classes(qw/
  Artist
  Employee
  CD
  Link
  Bookmark
  #dummy
  Track
  Tag
  /,
  { 'DBICTest::Schema' => [qw/
    LinerNotes
    OneKey
    #dummy
    TwoKeys
    Serialized
  /]},
  (
    'FourKeys',
    '#dummy',
    'SelfRef',
    'ArtistUndirectedMap',
    'ArtistSourceName',
    'Producer',
    'CD_to_Producer',
  ),
  qw/SelfRefAlias TreeLike TwoKeyTreeLike/
);

1;

package # hide from PAUSE
    DBICTest::Schema;

# load early so that `perl -It/lib -MDBICTest::Schema` keeps  working
use ANFANG;

use strict;
use warnings;
no warnings 'qw';

use base 'DBICTest::BaseSchema';

__PACKAGE__->mk_group_accessors(simple => 'custom_attr');

__PACKAGE__->load_classes(qw/
  Artist
  SequenceTest
  BindType
  Employee
  CD
  Genre
  Bookmark
  Link
  #dummy
  Track
  Tag
  Year2000CDs
  Year1999CDs
  CustomSql
  Money
  TimestampPrimaryKey
  /,
  { 'DBICTest::Schema' => [qw/
    LinerNotes
    Artwork
    Artwork_to_Artist
    Image
    Lyrics
    LyricVersion
    OneKey
    #dummy
    TwoKeys
    Serialized
  /]},
  (
    'FourKeys',
    'FourKeys_to_TwoKeys',
    '#dummy',
    'SelfRef',
    'ArtistUndirectedMap',
    'ArtistSourceName',
    'ArtistSubclass',
    'Producer',
    'CD_to_Producer',
    'Dummy',    # this is a real result class we remove in the hook below
  ),
  qw/SelfRefAlias TreeLike TwoKeyTreeLike Event NoPrimaryKey/,
  qw/Collection CollectionObject TypedObject Owners BooksInLibrary/,
  qw/ForceForeign Encoded/,
);

sub sqlt_deploy_hook {
  my ($self, $sqlt_schema) = @_;

  $sqlt_schema->drop_table('dummy');
}

1;

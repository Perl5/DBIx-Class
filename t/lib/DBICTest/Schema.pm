package # hide from PAUSE
    DBICTest::Schema;

use strict;
use warnings;
no warnings 'qw';

use base 'DBIx::Class::Schema';

use DBICTest::Util qw/populate_weakregistry assert_empty_weakregistry/;
use namespace::clean;

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
  qw/SelfRefAlias TreeLike TwoKeyTreeLike Event EventTZ NoPrimaryKey/,
  qw/Collection CollectionObject TypedObject Owners BooksInLibrary/,
  qw/ForceForeign Encoded/,
);

sub sqlt_deploy_hook {
  my ($self, $sqlt_schema) = @_;

  $sqlt_schema->drop_table('dummy');
}

my $weak_registry = {};

sub clone {
  my $self = shift->next::method(@_);
  populate_weakregistry ( $weak_registry, $self )
    if $INC{'Test/Builder.pm'};
  $self;
}

sub connection {
  my $self = shift->next::method(@_);

  if ($INC{'Test/Builder.pm'}) {
    populate_weakregistry ( $weak_registry, $self->storage );

    my $cur_connect_call = $self->storage->on_connect_call;

    $self->storage->on_connect_call([
      (ref $cur_connect_call eq 'ARRAY'
        ? @$cur_connect_call
        : ($cur_connect_call || ())
      ),
      [sub {
        populate_weakregistry( $weak_registry, shift->_dbh )
      }],
    ]);
  }

  $self;
}

END {
  assert_empty_weakregistry($weak_registry, 'quiet');
}

1;

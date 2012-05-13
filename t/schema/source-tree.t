use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema( no_connect => 1, no_deploy => 1 );

is_deeply($schema->source_tree, {
  Artist => {},
  ArtistSubclass => {},
  ArtistUndirectedMap => {
    artist => 1
  },
  Artwork => {
    cd => 1
  },
  Artwork_to_Artist => {
    artist => 1,
    cd_artwork => 1
  },
  BindType => {},
  Bookmark => {
    link => 1
  },
  BooksInLibrary => {
    owners => 1
  },
  CD => {
    genre => 1,
    track => 1
  },
  CD_to_Producer => {
    cd => 1,
    producer => 1
  },
  Collection => {},
  CollectionObject => {
    collection => 1,
    typed_object => 1
  },
  CustomSql => {},
  Dummy => {},
  Employee => {
    encoded => 1
  },
  Encoded => {},
  Event => {},
  EventTZ => {},
  ForceForeign => {
    artist => 1
  },
  FourKeys => {},
  FourKeys_to_TwoKeys => {
    fourkeys => 1,
    twokeys => 1
  },
  Genre => {},
  Image => {
    cd_artwork => 1
  },
  LinerNotes => {
    cd => 1
  },
  Link => {},
  LyricVersion => {
    lyrics => 1
  },
  Lyrics => {
    track => 1
  },
  Money => {},
  NoPrimaryKey => {},
  OneKey => {},
  Owners => {},
  Producer => {},
  SelfRef => {},
  SelfRefAlias => {
    self_ref => 1
  },
  SequenceTest => {},
  Serialized => {},
  SourceNameArtists => {},
  Tag => {
    cd => 1
  },
  TimestampPrimaryKey => {},
  Track => {
    cd => 1
  },
  TreeLike => {},
  TwoKeyTreeLike => {},
  TwoKeys => {
    artist => 1,
    cd => 1
  },
  TypedObject => {}
}, 'got correct source tree');

use Devel::Dwarn;

my $sans_TwoKeys = {
  Artist => {},
  ArtistSubclass => {},
  ArtistUndirectedMap => {
    artist => 1
  },
  Artwork => {
    cd => 1
  },
  Artwork_to_Artist => {
    artist => 1,
    cd_artwork => 1
  },
  BindType => {},
  Bookmark => {
    link => 1
  },
  BooksInLibrary => {
    owners => 1
  },
  CD => {
    genre => 1,
    track => 1
  },
  CD_to_Producer => {
    cd => 1,
    producer => 1
  },
  Collection => {},
  CollectionObject => {
    collection => 1,
    typed_object => 1
  },
  CustomSql => {},
  Dummy => {},
  Employee => {
    encoded => 1
  },
  Encoded => {},
  Event => {},
  EventTZ => {},
  ForceForeign => {
    artist => 1
  },
  FourKeys => {},
  FourKeys_to_TwoKeys => {
    fourkeys => 1
  },
  Genre => {},
  Image => {
    cd_artwork => 1
  },
  LinerNotes => {
    cd => 1
  },
  Link => {},
  LyricVersion => {
    lyrics => 1
  },
  Lyrics => {
    track => 1
  },
  Money => {},
  NoPrimaryKey => {},
  OneKey => {},
  Owners => {},
  Producer => {},
  SelfRef => {},
  SelfRefAlias => {
    self_ref => 1
  },
  SequenceTest => {},
  Serialized => {},
  SourceNameArtists => {},
  Tag => {
    cd => 1
  },
  TimestampPrimaryKey => {},
  Track => {
    cd => 1
  },
  TreeLike => {},
  TwoKeyTreeLike => {},
  TypedObject => {}
};

is_deeply(
   $schema->source_tree({ limit_sources => ['TwoKeys'] }),
   $sans_TwoKeys,
   'got correct source tree with limit_sources => [ ... ]',
);

is_deeply(
   $schema->source_tree({ limit_sources => { TwoKeys => 1 } }),
   $sans_TwoKeys,
   'got correct source tree with limit_sources => { ... }',
);

# We probably also want a "collapsed" tree

done_testing;

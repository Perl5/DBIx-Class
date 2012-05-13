use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema( no_connect => 1, no_deploy => 1 );

use Devel::Dwarn;

is_deeply($schema->source_tree, {
  Artist => {},
  ArtistSubclass => {},
  ArtistUndirectedMap => {
    Artist => 1
  },
  Artwork => {
    CD => 1,
    Genre => 1,
    Track => 1
  },
  Artwork_to_Artist => {
    Artist => 1,
    Artwork => 1,
    CD => 1,
    Genre => 1,
    Track => 1
  },
  BindType => {},
  Bookmark => {
    Link => 1
  },
  BooksInLibrary => {
    Owners => 1
  },
  CD => {
    Genre => 1,
    Track => 1
  },
  CD_to_Producer => {
    CD => 1,
    Genre => 1,
    Producer => 1,
    Track => 1
  },
  Collection => {},
  CollectionObject => {
    Collection => 1,
    TypedObject => 1
  },
  CustomSql => {},
  Dummy => {},
  Employee => {
    Encoded => 1
  },
  Encoded => {},
  Event => {},
  EventTZ => {},
  ForceForeign => {
    Artist => 1
  },
  FourKeys => {},
  FourKeys_to_TwoKeys => {
    Artist => 1,
    CD => 1,
    FourKeys => 1,
    Genre => 1,
    Track => 1,
    TwoKeys => 1
  },
  Genre => {},
  Image => {
    Artwork => 1,
    CD => 1,
    Genre => 1,
    Track => 1
  },
  LinerNotes => {
    CD => 1,
    Genre => 1,
    Track => 1
  },
  Link => {},
  LyricVersion => {
    CD => 1,
    Lyrics => 1,
    Track => 1
  },
  Lyrics => {
    CD => 1,
    Track => 1
  },
  Money => {},
  NoPrimaryKey => {},
  OneKey => {},
  Owners => {},
  Producer => {},
  SelfRef => {},
  SelfRefAlias => {
    SelfRef => 1
  },
  SequenceTest => {},
  Serialized => {},
  SourceNameArtists => {},
  Tag => {
    CD => 1,
    Genre => 1,
    Track => 1
  },
  TimestampPrimaryKey => {},
  Track => {
    CD => 1
  },
  TreeLike => {},
  TwoKeyTreeLike => {},
  TwoKeys => {
    Artist => 1,
    CD => 1,
    Genre => 1,
    Track => 1
  },
  TypedObject => {}
}, 'got correct source tree');

use Devel::Dwarn;

my $sans_TwoKeys = {
  Artist => {},
  ArtistSubclass => {},
  ArtistUndirectedMap => {
    Artist => 1
  },
  Artwork => {
    CD => 1,
    Genre => 1,
    Track => 1
  },
  Artwork_to_Artist => {
    Artist => 1,
    Artwork => 1,
    CD => 1,
    Genre => 1,
    Track => 1
  },
  BindType => {},
  Bookmark => {
    Link => 1
  },
  BooksInLibrary => {
    Owners => 1
  },
  CD => {
    Genre => 1,
    Track => 1
  },
  CD_to_Producer => {
    CD => 1,
    Genre => 1,
    Producer => 1,
    Track => 1
  },
  Collection => {},
  CollectionObject => {
    Collection => 1,
    TypedObject => 1
  },
  CustomSql => {},
  Dummy => {},
  Employee => {
    Encoded => 1
  },
  Encoded => {},
  Event => {},
  EventTZ => {},
  ForceForeign => {
    Artist => 1
  },
  FourKeys => {},
  FourKeys_to_TwoKeys => {
    FourKeys => 1
  },
  Genre => {},
  Image => {
    Artwork => 1,
    CD => 1,
    Genre => 1,
    Track => 1
  },
  LinerNotes => {
    CD => 1,
    Genre => 1,
    Track => 1
  },
  Link => {},
  LyricVersion => {
    CD => 1,
    Lyrics => 1,
    Track => 1
  },
  Lyrics => {
    CD => 1,
    Track => 1
  },
  Money => {},
  NoPrimaryKey => {},
  OneKey => {},
  Owners => {},
  Producer => {},
  SelfRef => {},
  SelfRefAlias => {
    SelfRef => 1
  },
  SequenceTest => {},
  Serialized => {},
  SourceNameArtists => {},
  Tag => {
    CD => 1,
    Genre => 1,
    Track => 1
  },
  TimestampPrimaryKey => {},
  Track => {
    CD => 1
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

# We probably also want a "collapsed" tree thingy

done_testing;

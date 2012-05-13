use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema( no_connect => 1, no_deploy => 1 );

is_deeply($schema->source_tree, {
  "  ( SELECT a.*, cd.cdid AS cdid, cd.title AS title, cd.year AS year\n  FROM artist a\n  JOIN cd ON cd.artist = a.artistid\n  WHERE cd.year = ?)\n" => {},
  artist => {},
  artist_undirected_map => {
    artist => 1
  },
  artwork_to_artist => {
    artist => 1,
    cd => 1,
    cd_artwork => 1,
    genre => 1,
    track => 1
  },
  bindtype_test => {},
  bookmark => {
    link => 1
  },
  books => {
    owners => 1
  },
  cd => {
    genre => 1,
    track => 1
  },
  cd_artwork => {
    cd => 1,
    genre => 1,
    track => 1
  },
  cd_to_producer => {
    cd => 1,
    genre => 1,
    producer => 1,
    track => 1
  },
  collection => {},
  collection_object => {
    collection => 1,
    typed_object => 1
  },
  dummy => {},
  employee => {
    encoded => 1
  },
  encoded => {},
  event => {},
  forceforeign => {
    artist => 1
  },
  fourkeys => {},
  fourkeys_to_twokeys => {
    artist => 1,
    cd => 1,
    fourkeys => 1,
    genre => 1,
    track => 1,
    twokeys => 1
  },
  genre => {},
  images => {
    cd => 1,
    cd_artwork => 1,
    genre => 1,
    track => 1
  },
  liner_notes => {
    cd => 1,
    genre => 1,
    track => 1
  },
  link => {},
  lyric_versions => {
    cd => 1,
    lyrics => 1,
    track => 1
  },
  lyrics => {
    cd => 1,
    track => 1
  },
  money_test => {},
  noprimarykey => {},
  onekey => {},
  owners => {},
  producer => {},
  self_ref => {},
  self_ref_alias => {
    self_ref => 1
  },
  sequence_test => {},
  serialized => {},
  tags => {
    cd => 1,
    genre => 1,
    track => 1
  },
  timestamp_primary_key_test => {},
  track => {
    cd => 1
  },
  treelike => {},
  twokeys => {
    artist => 1,
    cd => 1,
    genre => 1,
    track => 1
  },
  twokeytreelike => {},
  typed_object => {},
}, 'got correct source tree');

is_deeply($schema->source_tree({ limit_sources => ['TwoKeys'] }), {
  "  ( SELECT a.*, cd.cdid AS cdid, cd.title AS title, cd.year AS year\n  FROM artist a\n  JOIN cd ON cd.artist = a.artistid\n  WHERE cd.year = ?)\n" => {},
  artist => {},
  artist_undirected_map => {
    artist => 1
  },
  artwork_to_artist => {
    artist => 1,
    cd => 1,
    cd_artwork => 1,
    genre => 1,
    track => 1
  },
  bindtype_test => {},
  bookmark => {
    link => 1
  },
  books => {
    owners => 1
  },
  cd => {
    genre => 1,
    track => 1
  },
  cd_artwork => {
    cd => 1,
    genre => 1,
    track => 1
  },
  cd_to_producer => {
    cd => 1,
    genre => 1,
    producer => 1,
    track => 1
  },
  collection => {},
  collection_object => {
    collection => 1,
    typed_object => 1
  },
  dummy => {},
  employee => {
    encoded => 1
  },
  encoded => {},
  event => {},
  forceforeign => {
    artist => 1
  },
  fourkeys => {},
  fourkeys_to_twokeys => {
    fourkeys => 1
  },
  genre => {},
  images => {
    cd => 1,
    cd_artwork => 1,
    genre => 1,
    track => 1
  },
  liner_notes => {
    cd => 1,
    genre => 1,
    track => 1
  },
  link => {},
  lyric_versions => {
    cd => 1,
    lyrics => 1,
    track => 1
  },
  lyrics => {
    cd => 1,
    track => 1
  },
  money_test => {},
  noprimarykey => {},
  onekey => {},
  owners => {},
  producer => {},
  self_ref => {},
  self_ref_alias => {
    self_ref => 1
  },
  sequence_test => {},
  serialized => {},
  tags => {
    cd => 1,
    genre => 1,
    track => 1
  },
  timestamp_primary_key_test => {},
  track => {
    cd => 1
  },
  treelike => {},
  twokeytreelike => {},
  typed_object => {}
}, 'got correct source tree with limit_sources => [ ... ]');

is_deeply($schema->source_tree({ limit_sources => { TwoKeys => 1 } }), {
  "  ( SELECT a.*, cd.cdid AS cdid, cd.title AS title, cd.year AS year\n  FROM artist a\n  JOIN cd ON cd.artist = a.artistid\n  WHERE cd.year = ?)\n" => {},
  artist => {},
  artist_undirected_map => {
    artist => 1
  },
  artwork_to_artist => {
    artist => 1,
    cd => 1,
    cd_artwork => 1,
    genre => 1,
    track => 1
  },
  bindtype_test => {},
  bookmark => {
    link => 1
  },
  books => {
    owners => 1
  },
  cd => {
    genre => 1,
    track => 1
  },
  cd_artwork => {
    cd => 1,
    genre => 1,
    track => 1
  },
  cd_to_producer => {
    cd => 1,
    genre => 1,
    producer => 1,
    track => 1
  },
  collection => {},
  collection_object => {
    collection => 1,
    typed_object => 1
  },
  dummy => {},
  employee => {
    encoded => 1
  },
  encoded => {},
  event => {},
  forceforeign => {
    artist => 1
  },
  fourkeys => {},
  fourkeys_to_twokeys => {
    fourkeys => 1
  },
  genre => {},
  images => {
    cd => 1,
    cd_artwork => 1,
    genre => 1,
    track => 1
  },
  liner_notes => {
    cd => 1,
    genre => 1,
    track => 1
  },
  link => {},
  lyric_versions => {
    cd => 1,
    lyrics => 1,
    track => 1
  },
  lyrics => {
    cd => 1,
    track => 1
  },
  money_test => {},
  noprimarykey => {},
  onekey => {},
  owners => {},
  producer => {},
  self_ref => {},
  self_ref_alias => {
    self_ref => 1
  },
  sequence_test => {},
  serialized => {},
  tags => {
    cd => 1,
    genre => 1,
    track => 1
  },
  timestamp_primary_key_test => {},
  track => {
    cd => 1
  },
  treelike => {},
  twokeytreelike => {},
  typed_object => {}
}, 'got correct source tree with limit_sources => { ... }');

# We probably also want a "collapsed" tree

done_testing;

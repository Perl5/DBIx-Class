package DBICTest::Schema::HelperRels;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->has_many(cds => 'DBICTest::Schema::CD', undef,
                                     { order_by => 'year' });
DBICTest::Schema::Artist->has_many(twokeys => 'DBICTest::Schema::TwoKeys');
DBICTest::Schema::Artist->has_many(onekeys => 'DBICTest::Schema::OneKey');

DBICTest::Schema::CD->belongs_to('artist', 'DBICTest::Schema::Artist');

DBICTest::Schema::CD->has_many(tracks => 'DBICTest::Schema::Track');
DBICTest::Schema::CD->has_many(tags => 'DBICTest::Schema::Tag');
DBICTest::Schema::CD->has_many(cd_to_producer => 'DBICTest::Schema::CD_to_Producer' => 'cd');

DBICTest::Schema::CD->might_have(liner_notes => 'DBICTest::Schema::LinerNotes',
                                  undef, { proxy => [ qw/notes/ ] });

DBICTest::Schema::SelfRefAlias->belongs_to(
  self_ref => 'DBICTest::Schema::SelfRef');
DBICTest::Schema::SelfRefAlias->belongs_to(
  alias => 'DBICTest::Schema::SelfRef');

DBICTest::Schema::SelfRef->has_many(
  aliases => 'DBICTest::Schema::SelfRefAlias' => 'self_ref');

DBICTest::Schema::Tag->belongs_to('cd', 'DBICTest::Schema::CD');

DBICTest::Schema::Track->belongs_to('cd', 'DBICTest::Schema::CD');
DBICTest::Schema::Track->belongs_to('disc', 'DBICTest::Schema::CD', 'cd');

DBICTest::Schema::TwoKeys->belongs_to('artist', 'DBICTest::Schema::Artist');
DBICTest::Schema::TwoKeys->belongs_to('cd', 'DBICTest::Schema::CD');

DBICTest::Schema::CD_to_Producer->belongs_to(
  'cd', 'DBICTest::Schema::CD',
  { 'foreign.cdid' => 'self.cd' }
);
DBICTest::Schema::CD_to_Producer->belongs_to(
  'producer', 'DBICTest::Schema::Producer',
  { 'foreign.producerid' => 'self.producer' }
);
DBICTest::Schema::Artist->has_many(
  'artist_undirected_maps', 'DBICTest::Schema::ArtistUndirectedMap',
  [{'foreign.id1' => 'self.artistid'}, {'foreign.id2' => 'self.artistid'}]
);
DBICTest::Schema::ArtistUndirectedMap->belongs_to(
  'artist1', 'DBICTest::Schema::Artist', 'id1');
DBICTest::Schema::ArtistUndirectedMap->belongs_to(
  'artist2', 'DBICTest::Schema::Artist', 'id2');
DBICTest::Schema::ArtistUndirectedMap->has_many(
  'mapped_artists', 'DBICTest::Schema::Artist',
  [{'foreign.artistid' => 'self.id1'}, {'foreign.artistid' => 'self.id2'}]);

# now the Helpers
DBICTest::Schema::CD->many_to_many( 'producers', 'cd_to_producer', 'producer');

1;

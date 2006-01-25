package DBICTest::Schema::BasicRels;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->add_relationship(
    cds => 'DBICTest::Schema::CD',
    { 'foreign.artist' => 'self.artistid' },
    { order_by => 'year', join_type => 'LEFT', cascade_delete => 1 }
);
DBICTest::Schema::Artist->add_relationship(
    twokeys => 'DBICTest::Schema::TwoKeys',
    { 'foreign.artist' => 'self.artistid' }
);
DBICTest::Schema::Artist->add_relationship(
    onekeys => 'DBICTest::Schema::OneKey',
    { 'foreign.artist' => 'self.artistid' }
);
DBICTest::Schema::Artist->add_relationship(
    artist_undirected_maps => 'DBICTest::Schema::ArtistUndirectedMap',
    [{'foreign.id1' => 'self.artistid'}, {'foreign.id2' => 'self.artistid'}],
    { accessor => 'multi' }
);
DBICTest::Schema::ArtistUndirectedMap->add_relationship(
    'mapped_artists', 'DBICTest::Schema::Artist',
    [{'foreign.artistid' => 'self.id1'}, {'foreign.artistid' => 'self.id2'}]
);
DBICTest::Schema::CD->add_relationship(
    artist => 'DBICTest::Schema::Artist',
    { 'foreign.artistid' => 'self.artist' },
    { accessor => 'filter' },
);
DBICTest::Schema::CD->add_relationship(
    tracks => 'DBICTest::Schema::Track',
    { 'foreign.cd' => 'self.cdid' },
    { join_type => 'LEFT', cascade_delete => 1 }
);
DBICTest::Schema::CD->add_relationship(
    tags => 'DBICTest::Schema::Tag',
    { 'foreign.cd' => 'self.cdid' },
    { join_type => 'LEFT', cascade_delete => 1 }
);
#DBICTest::Schema::CD->might_have(liner_notes => 'DBICTest::Schema::LinerNotes' => qw/notes/);
DBICTest::Schema::CD->add_relationship(
    liner_notes => 'DBICTest::Schema::LinerNotes',
    { 'foreign.liner_id' => 'self.cdid' },
    { join_type => 'LEFT', accessor => 'single' }
);
DBICTest::Schema::CD->add_relationship(
    cd_to_producer => 'DBICTest::Schema::CD_to_Producer',
    { 'foreign.cd' => 'self.cdid' },
    { join_type => 'LEFT', cascade_delete => 1 }
);

DBICTest::Schema::SelfRefAlias->add_relationship(
    self_ref => 'DBICTest::Schema::SelfRef',
    { 'foreign.id' => 'self.self_ref' },
    { accessor     => 'single' }

);
DBICTest::Schema::SelfRefAlias->add_relationship(
    alias => 'DBICTest::Schema::SelfRef',
    { 'foreign.id' => 'self.alias' },
    { accessor     => 'single' }
);

DBICTest::Schema::SelfRef->add_relationship(
    aliases => 'DBICTest::Schema::SelfRefAlias',
    { 'foreign.self_ref' => 'self.id' },
    { accessor => 'multi' }
);

DBICTest::Schema::Tag->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' },
    { accessor => 'single' }
);

DBICTest::Schema::Track->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' },
    { accessor => 'single' }
);

DBICTest::Schema::TwoKeys->add_relationship(
    artist => 'DBICTest::Schema::Artist',
    { 'foreign.artistid' => 'self.artist' }
);
DBICTest::Schema::TwoKeys->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' }
);

DBICTest::Schema::CD_to_Producer->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' }
);
DBICTest::Schema::CD_to_Producer->add_relationship(
    producer => 'DBICTest::Schema::Producer',
    { 'foreign.producerid' => 'self.producer' }
);

# now the Helpers
DBICTest::Schema::CD->many_to_many( 'producers', 'cd_to_producer', 'producer');

1;

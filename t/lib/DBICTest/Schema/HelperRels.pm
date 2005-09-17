package DBICTest::Schema::BasicRels;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->add_relationship(
    cds => 'DBICTest::Schema::CD',
    { 'foreign.artist' => 'self.artistid' },
    { order_by => 'year' }
);
DBICTest::Schema::Artist->add_relationship(
    twokeys => 'DBICTest::Schema::TwoKeys',
    { 'foreign.artist' => 'self.artistid' }
);
DBICTest::Schema::Artist->add_relationship(
    onekeys => 'DBICTest::Schema::OneKey',
    { 'foreign.artist' => 'self.artistid' }
);

DBICTest::Schema::CD->has_one('artist', 'DBICTest::Schema::Artist');
#DBICTest::Schema::CD->add_relationship(
#    artist => 'DBICTest::Schema::Artist',
#    { 'foreign.artistid' => 'self.artist' },
#);
DBICTest::Schema::CD->add_relationship(
    tracks => 'DBICTest::Schema::Track',
    { 'foreign.cd' => 'self.cdid' }
);
DBICTest::Schema::CD->add_relationship(
    tags => 'DBICTest::Schema::Tag',
    { 'foreign.cd' => 'self.cdid' }
);
#DBICTest::Schema::CD->might_have(liner_notes => 'DBICTest::Schema::LinerNotes' => qw/notes/);
DBICTest::Schema::CD->add_relationship(
    liner_notes => 'DBICTest::Schema::LinerNotes',
    { 'foreign.liner_id' => 'self.cdid' },
    { join_type => 'LEFT' }
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

DBICTest::Schema::Tag->has_one('cd', 'DBICTest::Schema::CD');
#DBICTest::Schema::Tag->add_relationship(
#    cd => 'DBICTest::Schema::CD',
#    { 'foreign.cdid' => 'self.cd' }
#);

DBICTest::Schema::Track->has_one('cd', 'DBICTest::Schema::CD');
#DBICTest::Schema::Track->add_relationship(
#    cd => 'DBICTest::Schema::CD',
#    { 'foreign.cdid' => 'self.cd' }
#);

DBICTest::Schema::TwoKeys->has_one('artist', 'DBICTest::Schema::Artist');
# DBICTest::Schema::TwoKeys->add_relationship(
#    artist => 'DBICTest::Schema::Artist',
#    { 'foreign.artistid' => 'self.artist' }
# );
DBICTest::Schema::TwoKeys->has_one('cd', 'DBICTest::Schema::CD');
#DBICTest::Schema::TwoKeys->add_relationship(
#    cd => 'DBICTest::Schema::CD',
#    { 'foreign.cdid' => 'self.cd' }
#);

1;

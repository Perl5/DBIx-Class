package DBICTest::Schema::CD;

use base 'DBIx::Class::Core';

DBICTest::Schema::CD->table('cd');
DBICTest::Schema::CD->add_columns(qw/cdid artist title year/);
DBICTest::Schema::CD->set_primary_key('cdid');
DBICTest::Schema::CD->add_relationship(
    artist => 'DBICTest::Schema::Artist',
    { 'foreign.artistid' => 'self.artist' }
);
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
    { join_type => 'LEFT' });

1;

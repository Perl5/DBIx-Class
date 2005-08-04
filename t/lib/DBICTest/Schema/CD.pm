package DBICTest::CD;

use base 'DBIx::Class::Core';

DBICTest::CD->table('cd');
DBICTest::CD->add_columns(qw/cdid artist title year/);
DBICTest::CD->set_primary_key('cdid');
DBICTest::CD->add_relationship(
    artist => 'DBICTest::Artist',
    { 'foreign.artistid' => 'self.artist' }
);
DBICTest::CD->add_relationship(
    tracks => 'DBICTest::Track',
    { 'foreign.cd' => 'self.cdid' }
);
DBICTest::CD->add_relationship(
    tags => 'DBICTest::Tag',
    { 'foreign.cd' => 'self.cdid' }
);
#DBICTest::CD->might_have(liner_notes => 'DBICTest::LinerNotes' => qw/notes/);

1;

package DBICTest::LinerNotes;

use base qw/DBIx::Class::Core/;

DBICTest::LinerNotes->table('liner_notes');
DBICTest::LinerNotes->add_columns(qw/liner_id notes/);
DBICTest::LinerNotes->set_primary_key('liner_id');

1;

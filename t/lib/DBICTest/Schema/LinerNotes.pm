package DBICTest::Schema::LinerNotes;

use base qw/DBIx::Class::Core/;

DBICTest::Schema::LinerNotes->table('liner_notes');
DBICTest::Schema::LinerNotes->add_columns(qw/liner_id notes/);
DBICTest::Schema::LinerNotes->set_primary_key('liner_id');

1;

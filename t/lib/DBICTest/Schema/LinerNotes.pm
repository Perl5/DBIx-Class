package DBICTest::Schema::LinerNotes;

use base qw/DBIx::Class::Core/;

DBICTest::Schema::LinerNotes->table('liner_notes');
DBICTest::Schema::LinerNotes->add_columns(
  'liner_id' => {
    data_type => 'integer',
  },
  'notes' => {
    data_type => 'varchar',
  },
);
DBICTest::Schema::LinerNotes->set_primary_key('liner_id');

1;

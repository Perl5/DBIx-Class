package DBICTest::Schema::Tag;

use base qw/DBIx::Class::Core/;

DBICTest::Schema::Tag->table('tags');
DBICTest::Schema::Tag->add_columns(
  'tagid' => {
    data_type => 'varchar',
    is_auto_increment => 1,
  },
  'cd' => {
    data_type => 'integer',
  },
  'tag' => {
    data_type => 'varchar'
  },
);
DBICTest::Schema::Tag->set_primary_key('tagid');

1;

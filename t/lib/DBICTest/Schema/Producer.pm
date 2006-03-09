package # hide from PAUSE 
    DBICTest::Schema::Producer;

use base 'DBIx::Class::Core';

__PACKAGE__->table('producer');
__PACKAGE__->add_columns(
  'producerid' => {
    data_type => 'integer',
    is_auto_increment => 1
  },
  'name' => {
    data_type => 'varchar',
  },
);
__PACKAGE__->set_primary_key('producerid');

1;

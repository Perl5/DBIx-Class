package DBICTest::Schema::SelfRef;

use base 'DBIx::Class::Core';

__PACKAGE__->table('self_ref');
__PACKAGE__->add_columns(
  'id' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'name' => {
    data_type => 'varchar',
  },
);
__PACKAGE__->set_primary_key('id');

1;

package # hide from PAUSE 
    DBICTest::Schema::Label;

use base 'DBIx::Class::Core';

__PACKAGE__->table('label');
__PACKAGE__->add_columns(
  'labelid' => {
    data_type         => 'integer',
    is_auto_increment => 1
  },
  'name' => {
    data_type   => 'varchar',
    size        => 100,
    is_nullable => 1,
  },
);
__PACKAGE__->set_primary_key('labelid');

__PACKAGE__->has_many(
  agents => 'DBICTest::Schema::Agent',
  undef,
  { prefetch => 'artists' }
);

1;

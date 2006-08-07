package # hide from PAUSE 
    DBICTest::Schema::Agent;

use base 'DBIx::Class::Core';

__PACKAGE__->table('agent');
__PACKAGE__->add_columns(
  'agentid' => {
    data_type         => 'integer',
    is_auto_increment => 1
  },
  'label' => {
    data_type => 'integer',
  },
  'name' => {
    data_type   => 'varchar',
    size        => 100,
    is_nullable => 1,
  },
);
__PACKAGE__->set_primary_key('agentid');

__PACKAGE__->has_many( artists => 'DBICTest::Schema::Artist' );
__PACKAGE__->belongs_to( label => 'DBICTest::Schema::Label' );

1;

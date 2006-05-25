package # hide from PAUSE 
    DBICTest::Schema::TreeLike;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('treelike');
__PACKAGE__->add_columns(
  'id' => { data_type => 'integer', is_auto_increment => 1 },
  'parent' => { data_type => 'integer' },
  'name' => { data_type => 'varchar',
    size      => 100,
 },
);
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->belongs_to('parent', 'DBICTest::Schema::TreeLike',
                          { 'foreign.id' => 'self.parent' });

1;

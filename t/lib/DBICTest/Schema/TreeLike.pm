package DBICTest::Schema::TreeLike;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto::SQLite Core/);

__PACKAGE__->table('treelike');
__PACKAGE__->add_columns(
  'id' => { data_type => 'integer', is_auto_increment => 1 },
  'parent' => { data_type => 'integer' },
  'name' => { data_type => 'varchar' },
);
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->belongs_to('parent', 'TreeLike',
                          { 'foreign.id' => 'self.parent' });

1;

package # hide from PAUSE 
    DBICTest::Schema::Employee::PositionedAdjacencyList;

use base 'DBIx::Class';

__PACKAGE__->load_components(qw(
    Tree::AdjacencyList
    Positioned
    PK::Auto
    Core
));

__PACKAGE__->table('employees_positioned_adjacencylist');

__PACKAGE__->add_columns(
    employee_id => {
        data_type => 'integer',
        is_auto_increment => 1
    },
    parent_id => {
        data_type => 'integer',
        is_nullable => 1,
    },
    position => {
        data_type => 'integer',
    },
    name => {
        data_type => 'varchar',
        size      => 100,
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('employee_id');
__PACKAGE__->position_column('position');
__PACKAGE__->parent_column('parent_id');

__PACKAGE__->mk_classdata('field_name_for', {
    employee_id => 'primary key',
    parent_id   => 'parent id',
    position    => 'list position',
    name        => 'employee name',
});

1;

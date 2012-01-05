package # hide from PAUSE
    DBICTest::Schema::Employee;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->load_components(qw( Ordered ));

__PACKAGE__->table('employee');

__PACKAGE__->add_columns(
    employee_id => {
        data_type => 'integer',
        is_auto_increment => 1
    },
    position => {
        data_type => 'integer',
    },
    group_id => {
        data_type => 'integer',
        is_nullable => 1,
    },
    group_id_2 => {
        data_type => 'integer',
        is_nullable => 1,
    },
    group_id_3 => {
        data_type => 'integer',
        is_nullable => 1,
    },
    name => {
        data_type => 'varchar',
        size      => 100,
        is_nullable => 1,
    },
    encoded => {
        data_type => 'integer',
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('employee_id');
__PACKAGE__->position_column('position');

# Do not add unique constraints here - different groups are used throughout
# the ordered tests

__PACKAGE__->belongs_to (secretkey => 'DBICTest::Schema::Encoded', 'encoded', {
  join_type => 'left'
});

1;

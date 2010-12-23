package    # hide from PAUSE
    DBICTest::Schema::StorageFlagPole;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('storage_flag_pole');
__PACKAGE__->add_columns(
    'id' => {
        data_type     => 'datetime',
        default_value => \'current_timestamp'
    },
    'name' => { data_type => 'text', },
);
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->resultset_attributes(
    { storage => { use_insert_returning => 0 } } );

1;

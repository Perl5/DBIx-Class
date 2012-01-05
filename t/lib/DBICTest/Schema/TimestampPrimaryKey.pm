package # hide from PAUSE
    DBICTest::Schema::TimestampPrimaryKey;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('timestamp_primary_key_test');

__PACKAGE__->add_columns(
  'id' => {
    data_type => 'timestamp',
    default_value => \'current_timestamp',
  },
);

__PACKAGE__->set_primary_key('id');

1;

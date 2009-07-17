package # hide from PAUSE 
    DBICTest::Schema::SingleBlob;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('single_blob_test');

__PACKAGE__->add_columns(
  'id' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'blob' => {
    data_type => 'blob',
    is_nullable => 1,
  },
  'foo' => {
    data_type => 'varchar',
    is_nullable => 1,
  }
);

__PACKAGE__->set_primary_key('id');

1;

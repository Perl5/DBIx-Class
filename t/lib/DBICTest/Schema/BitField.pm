package # hide from PAUSE 
    DBICTest::Schema::BitField;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('bitfield_test');
__PACKAGE__->add_columns(
  'id' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'bitfield_1' => {
    data_type => 'bit',
    size => 1,
    is_nullable => 1,
  },
  'bitfield_32' => {
    data_type => 'bit',
    size => 32,
    is_nullable => 1,
  },
  'bitfield_64' => {
    data_type => 'bit',
    size => 64,
    is_nullable => 1,
  },
);
__PACKAGE__->set_primary_key('id');

1;

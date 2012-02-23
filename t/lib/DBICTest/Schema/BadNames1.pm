package # hide from PAUSE
    DBICTest::Schema::BadNames1;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('bad_names_1');

__PACKAGE__->add_columns(
  id => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'good_name' => {
    data_type => 'int',
    is_nullable => 1,
    sql_alias => 'stupid_name',
  },
);
__PACKAGE__->set_primary_key('id');
1;

package # hide from PAUSE
    DBICTest::Schema::PunctuatedColumnName;

use base qw/DBICTest::BaseResult/;

__PACKAGE__->table('punctuated_column_name');
__PACKAGE__->add_columns(
  'id' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  q{foo ' bar} => {
    data_type => 'integer',
    is_nullable => 1,
    accessor => 'foo_bar',
  },
  q{bar/baz} => {
    data_type => 'integer',
    is_nullable => 1,
    accessor => 'bar_baz',
  },
  q{baz;quux} => {
    data_type => 'integer',
    is_nullable => 1,
    accessor => 'bar_quux',
  },
);

__PACKAGE__->set_primary_key('id');

1;

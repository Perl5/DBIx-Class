package # hide from PAUSE
    DBICTest::Schema::VaryingMAX;

use base qw/DBICTest::BaseResult/;

# Test VARCHAR(MAX) type for MSSQL (used in ADO tests)

__PACKAGE__->table('varying_max_test');

__PACKAGE__->add_columns(
  'id' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'varchar_max' => {
    data_type => 'varchar',
    size => 'max',
    is_nullable => 1,
  },
  'nvarchar_max' => {
    data_type => 'nvarchar',
    size => 'max',
    is_nullable => 1,
  },
  'varbinary_max' => {
    data_type => 'varbinary(max)', # alternately
    size => undef,
    is_nullable => 1,
  },
);

__PACKAGE__->set_primary_key('id');

1;

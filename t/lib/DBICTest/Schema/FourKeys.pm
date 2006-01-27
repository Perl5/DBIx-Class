package DBICTest::Schema::FourKeys;

use base 'DBIx::Class::Core';

DBICTest::Schema::FourKeys->table('fourkeys');
DBICTest::Schema::FourKeys->add_columns(
  'foo' => { data_type => 'integer' },
  'bar' => { data_type => 'integer' },
  'hello' => { data_type => 'integer' },
  'goodbye' => { data_type => 'integer' },
);
DBICTest::Schema::FourKeys->set_primary_key(qw/foo bar hello goodbye/);

1;

package # hide from PAUSE
    DBICTest::Schema::TwoKeys;

use base 'DBIx::Class::Core';

DBICTest::Schema::TwoKeys->table('twokeys');
DBICTest::Schema::TwoKeys->add_columns(
  'artist' => { data_type => 'integer' },
  'cd' => { data_type => 'integer' },
);
DBICTest::Schema::TwoKeys->set_primary_key(qw/artist cd/);

1;

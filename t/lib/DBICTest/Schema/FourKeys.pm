package DBICTest::Schema::FourKeys;

use base 'DBIx::Class::Core';

DBICTest::Schema::FourKeys->table('fourkeys');
DBICTest::Schema::FourKeys->add_columns(qw/foo bar hello goodbye/);
DBICTest::Schema::FourKeys->set_primary_key(qw/foo bar hello goodbye/);

1;

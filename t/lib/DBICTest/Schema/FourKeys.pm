package DBICTest::FourKeys;

use base 'DBIx::Class::Core';

DBICTest::FourKeys->table('fourkeys');
DBICTest::FourKeys->add_columns(qw/foo bar hello goodbye/);
DBICTest::FourKeys->set_primary_key(qw/foo bar hello goodbye/);

1;

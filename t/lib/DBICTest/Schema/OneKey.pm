package DBICTest::OneKey;

use base 'DBIx::Class::Core';

DBICTest::OneKey->table('onekey');
DBICTest::OneKey->add_columns(qw/id artist cd/);
DBICTest::OneKey->set_primary_key('id');


1;

package DBICTest::Schema::OneKey;

use base 'DBIx::Class::Core';

DBICTest::Schema::OneKey->table('onekey');
DBICTest::Schema::OneKey->add_columns(qw/id artist cd/);
DBICTest::Schema::OneKey->set_primary_key('id');


1;

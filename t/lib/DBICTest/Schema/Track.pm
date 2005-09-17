package DBICTest::Schema::Track;

use base 'DBIx::Class::Core';

DBICTest::Schema::Track->table('track');
DBICTest::Schema::Track->add_columns(qw/trackid cd position title/);
DBICTest::Schema::Track->set_primary_key('trackid');

1;

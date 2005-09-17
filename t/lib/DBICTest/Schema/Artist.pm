package DBICTest::Schema::Artist;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->table('artist');
DBICTest::Schema::Artist->add_columns(qw/artistid name/);
DBICTest::Schema::Artist->set_primary_key('artistid');

1;

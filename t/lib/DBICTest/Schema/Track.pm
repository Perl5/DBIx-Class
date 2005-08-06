package DBICTest::Schema::Track;

use base 'DBIx::Class::Core';

DBICTest::Schema::Track->table('track');
DBICTest::Schema::Track->add_columns(qw/trackid cd position title/);
DBICTest::Schema::Track->set_primary_key('trackid');
DBICTest::Schema::Track->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' }
);

1;

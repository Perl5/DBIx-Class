package DBICTest::Track;

use base 'DBIx::Class::Core';

DBICTest::Track->table('track');
DBICTest::Track->add_columns(qw/trackid cd position title/);
DBICTest::Track->set_primary_key('trackid');
DBICTest::Track->add_relationship(
    cd => 'DBICTest::CD',
    { 'foreign.cdid' => 'self.cd' }
);

1;

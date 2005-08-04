package DBICTest::Tag;

use base qw/DBIx::Class::Core/;

DBICTest::Tag->table('tags');
DBICTest::Tag->add_columns(qw/tagid cd tag/);
DBICTest::Tag->set_primary_key('tagid');
DBICTest::Tag->add_relationship(
    cd => 'DBICTest::CD',
    { 'foreign.cdid' => 'self.cd' }
);

1;

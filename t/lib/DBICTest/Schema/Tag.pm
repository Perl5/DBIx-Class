package DBICTest::Schema::Tag;

use base qw/DBIx::Class::Core/;

DBICTest::Schema::Tag->table('tags');
DBICTest::Schema::Tag->add_columns(qw/tagid cd tag/);
DBICTest::Schema::Tag->set_primary_key('tagid');
DBICTest::Schema::Tag->add_relationship(
    cd => 'DBICTest::Schema::CD',
    { 'foreign.cdid' => 'self.cd' }
);

1;

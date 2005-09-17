package DBICTest::Schema::Tag;

use base qw/DBIx::Class::Core/;

DBICTest::Schema::Tag->table('tags');
DBICTest::Schema::Tag->add_columns(qw/tagid cd tag/);
DBICTest::Schema::Tag->set_primary_key('tagid');

1;

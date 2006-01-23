package DBICTest::Schema::CD;

use base 'DBIx::Class::Core';

DBICTest::Schema::CD->table('cd');
DBICTest::Schema::CD->add_columns(qw/cdid artist title year/);
DBICTest::Schema::CD->set_primary_key('cdid');
DBICTest::Schema::CD->add_unique_constraint(artist_title => [ qw/artist title/ ]);

1;

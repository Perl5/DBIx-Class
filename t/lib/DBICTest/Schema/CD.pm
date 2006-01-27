package DBICTest::Schema::CD;

use base 'DBIx::Class::Core';

DBICTest::Schema::CD->table('cd');
DBICTest::Schema::CD->add_columns(
  'cdid' => {
    data_type => 'integer',
    is_auto_increment => 1,
  },
  'artist' => {
    data_type => 'integer',
  },
  'title' => {
    data_type => 'varchar',
  },
  'year' => {
    data_type => 'varchar',
  },
);
DBICTest::Schema::CD->set_primary_key('cdid');
DBICTest::Schema::CD->add_unique_constraint(artist_title => [ qw/artist title/ ]);

1;

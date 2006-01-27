package DBICTest::Schema::Artist;

use base 'DBIx::Class::Core';

DBICTest::Schema::Artist->table('artist');
DBICTest::Schema::Artist->add_columns(
  'artistid' => {
    data_type => 'integer',
    is_auto_increment => 1
  },
  'name' => {
    data_type => 'varchar',
    is_nullable => 1,
  },
);
DBICTest::Schema::Artist->set_primary_key('artistid');

__PACKAGE__->mk_classdata('field_name_for', {
    artistid    => 'primary key',
    name        => 'artist name',
});

1;

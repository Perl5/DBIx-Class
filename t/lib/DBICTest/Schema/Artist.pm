package # hide from PAUSE 
    DBICTest::Schema::Artist;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components('Positioned','PK::Auto');

DBICTest::Schema::Artist->table('artist');
DBICTest::Schema::Artist->add_columns(
  'artistid' => {
    data_type => 'integer',
    is_auto_increment => 1
  },
  'name' => {
    data_type => 'varchar',
    size      => 100,
    is_nullable => 1,
  },
  position => {
    data_type => 'integer',
  },
);
DBICTest::Schema::Artist->set_primary_key('artistid');
__PACKAGE__->position_column('position');

__PACKAGE__->mk_classdata('field_name_for', {
    artistid    => 'primary key',
    name        => 'artist name',
    position    => 'list position',
});

1;

package # hide from PAUSE 
    DBICTest::Schema::ArtistOracle;

use base 'DBIx::Class::Core';

__PACKAGE__->table('artist_oracle');
__PACKAGE__->source_info({
    "source_info_key_A" => "source_info_value_A",
    "source_info_key_B" => "source_info_value_B",
    "source_info_key_C" => "source_info_value_C",
});
__PACKAGE__->add_columns(
  'artistid' => {
    data_type => 'integer',
    auto_nextval => 1,
    sequence => 'artist_oracle_seq',
  },
  'otherid' => {
    data_type => 'integer',
    auto_nextval => 1,
    sequence => 'artist_oracle_otherid_seq',
  },
  'nonpriid' => {
    data_type => 'integer',
    auto_nextval => 1,
    sequence => 'artist_oracle_nonpriid_seq',
  },
  'name' => {
    data_type => 'varchar',
    size      => 100,
    is_nullable => 1,
  },
);
__PACKAGE__->set_primary_key('artistid', 'otherid');

1;

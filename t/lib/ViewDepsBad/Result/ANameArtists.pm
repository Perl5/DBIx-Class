package    # hide from PAUSE
    ViewDepsBad::Result::ANameArtists;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('a_name_artists');
__PACKAGE__->result_source_instance->view_definition(
    "SELECT id,name FROM artist WHERE name like 'a%'"
);

__PACKAGE__->add_columns(
    id   => { data_type => 'integer', is_auto_increment => 1 },
    name => { data_type => 'text' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many( 'cds', 'ViewDeps::Result::CD',
    { "foreign.artist" => "self.id" },
);

1;

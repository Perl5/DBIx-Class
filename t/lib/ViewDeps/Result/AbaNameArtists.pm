package    # hide from PAUSE
    ViewDeps::Result::AbaNameArtists;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('aba_name_artists');
__PACKAGE__->result_source_instance->view_definition(
    "SELECT id,name FROM ab_name_artists WHERE name like 'aba%'" );
__PACKAGE__->result_source_instance->deploy_depends_on(
    ["ViewDeps::Result::AbNameArtists"] );

__PACKAGE__->add_columns(
    id   => { data_type => 'integer', is_auto_increment => 1 },
    name => { data_type => 'text' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many( 'cds', 'ViewDeps::Result::CD',
    { "foreign.artist" => "self.id" },
);

1;

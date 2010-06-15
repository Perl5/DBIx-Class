package    # hide from PAUSE
    ViewDepsBad::Result::AbaNameArtistsAnd2010CDsWithManyTracks;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('aba_name_artists_and_2010_cds_with_many_tracks');
__PACKAGE__->result_source_instance->view_definition(
    "SELECT aba.id,aba.name,cd.title,cd.year,cd.number_tracks FROM aba_name_artists aba JOIN year_2010_cds_with_many_tracks cd on (aba.id = cd.artist)"
);
__PACKAGE__->result_source_instance->deploy_depends_on(
    ["ViewDepsBad::Result::AbNameArtists","ViewDepsBad::Result::Year2010CDsWithManyTracks"] );

__PACKAGE__->add_columns(
    id            => { data_type => 'integer', is_auto_increment => 1 },
    name          => { data_type => 'text' },
    title         => { data_type => 'text' },
    year          => { data_type => 'integer' },
    number_tracks => { data_type => 'integer' },
);

__PACKAGE__->set_primary_key('id');

1;

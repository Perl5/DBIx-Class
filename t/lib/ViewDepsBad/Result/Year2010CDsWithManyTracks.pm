package    # hide from PAUSE
    ViewDepsBad::Result::Year2010CDsWithManyTracks;

use strict;
use warnings;
use base 'ViewDepsBad::Result::Year2010CDs';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('year_2010_cds_with_many_tracks');
__PACKAGE__->result_source_instance->view_definition(
    "SELECT cd.id,cd.title,cd.artist,cd.year,cd.number_tracks,art.file FROM year_2010_cds cd JOIN artwork art on art.cd = cd.id WHERE cd.number_tracks > 10"
);

__PACKAGE__->result_source_instance->deploy_depends_on(
    ["ViewDepsBad::Result::Year2010CDs"] );

__PACKAGE__->add_columns(
    id            => { data_type => 'integer', is_auto_increment => 1 },
    title         => { data_type => 'text' },
    artist        => { data_type => 'integer', is_nullable       => 0 },
    year          => { data_type => 'integer' },
    number_tracks => { data_type => 'integer' },
    file       => { data_type => 'integer' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to( 'artist', 'ViewDepsBad::Result::Artist',
    { "foreign.id" => "self.artist" },
);

__PACKAGE__->has_many( 'tracks', 'ViewDepsBad::Result::Track',
    { "foreign.cd" => "self.id" },
);

1;

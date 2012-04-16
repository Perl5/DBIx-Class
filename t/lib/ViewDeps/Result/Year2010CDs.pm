package    # hide from PAUSE
    ViewDeps::Result::Year2010CDs;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('year_2010_cds');
__PACKAGE__->result_source_instance->view_definition(
    "SELECT id,title,artist,year,number_tracks FROM cd WHERE year = '2010'");

__PACKAGE__->add_columns(
    id            => { data_type => 'integer', is_auto_increment => 1 },
    title         => { data_type => 'text' },
    artist        => { data_type => 'integer', is_nullable       => 0 },
    year          => { data_type => 'integer' },
    number_tracks => { data_type => 'integer' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to( 'artist', 'ViewDeps::Result::Artist',
    { "foreign.id" => "self.artist" },
);

__PACKAGE__->has_many( 'tracks', 'ViewDeps::Result::Track',
    { "foreign.cd" => "self.id" },
);

1;

package    # hide from PAUSE
    ViewDepsBad::Result::TrackNumberFives;

use strict;
use warnings;
use base 'ViewDepsBad::Result::Track';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('track_number_fives');
__PACKAGE__->result_source_instance->view_definition(
    "SELECT id,title,cd,track_number FROM track WHERE track_number = '5'");

__PACKAGE__->add_columns(
    id           => { data_type => 'integer', is_auto_increment => 1 },
    title        => { data_type => 'text' },
    cd           => { data_type => 'integer' },
    track_number => { data_type => 'integer' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to( 'cd', 'ViewDepsBad::Result::CD',
    { "foreign.id" => "self.cd" },
);

1;

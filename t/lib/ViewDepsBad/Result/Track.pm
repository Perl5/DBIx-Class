package    # hide from PAUSE
    ViewDepsBad::Result::Track;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table('track');

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

package    # hide from PAUSE
    ViewDepsBad::Result::CD;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table('cd');

__PACKAGE__->add_columns(
    id            => { data_type => 'integer', is_auto_increment => 1 },
    title         => { data_type => 'text' },
    artist        => { data_type => 'integer', is_nullable       => 0 },
    year          => { data_type => 'integer' },
    number_tracks => { data_type => 'integer' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to( 'artist', 'ViewDepsBad::Result::Artist',
    { "foreign.id" => "self.artist" },
);

__PACKAGE__->has_many( 'tracks', 'ViewDepsBad::Result::Track',
    { "foreign.cd" => "self.id" },
);

1;

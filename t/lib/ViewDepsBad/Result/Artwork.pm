package    # hide from PAUSE
    ViewDepsBad::Result::Artwork;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table('artwork');

__PACKAGE__->add_columns(
    id            => { data_type => 'integer', is_auto_increment => 1 },
    cd         => { data_type => 'integer' },
    file          => { data_type => 'text' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to( 'cd', 'ViewDepsBad::Result::CD',
    { "foreign.id" => "self.cd" },
);

1;

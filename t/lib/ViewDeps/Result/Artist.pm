package    # hide from PAUSE
    ViewDeps::Result::Artist;

use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table('artist');

__PACKAGE__->add_columns(
    id   => { data_type => 'integer', is_auto_increment => 1 },
    name => { data_type => 'text' },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many( 'cds', 'ViewDeps::Result::CD',
    { "foreign.artist" => "self.id" },
);

1;

package MyApp::Schema::Result::Artist;

use warnings;
use strict;

use base qw( DBIx::Class::Core );

__PACKAGE__->table('artist');

__PACKAGE__->add_columns(
  artistid => {
    data_type => 'integer',
    is_auto_increment => 1
  },
  name => {
    data_type => 'text',
  },
);

__PACKAGE__->set_primary_key('artistid');

__PACKAGE__->add_unique_constraint([qw( name )]);

__PACKAGE__->has_many('cds' => 'MyApp::Schema::Result::Cd', 'artistid');

1;


package MyApp::Schema::Result::Cd;

use warnings;
use strict;

use base qw( DBIx::Class::Core );

__PACKAGE__->table('cd');

__PACKAGE__->add_columns(
  cdid => {
    data_type => 'integer',
    is_auto_increment => 1
  },
  artistid => {
    data_type => 'integer',
  },
  title => {
    data_type => 'text',
  },
  year => {
    data_type => 'datetime',
    is_nullable => 1,
  },
);

__PACKAGE__->set_primary_key('cdid');

__PACKAGE__->add_unique_constraint([qw( title artistid )]);

__PACKAGE__->belongs_to('artist' => 'MyApp::Schema::Result::Artist', 'artistid');
__PACKAGE__->has_many('tracks' => 'MyApp::Schema::Result::Track', 'cdid');

1;

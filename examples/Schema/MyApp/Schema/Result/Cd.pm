package MyApp::Schema::Result::Cd;

use warnings;
use strict;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('cd');

__PACKAGE__->add_columns(qw/ cdid artist title year /);

__PACKAGE__->set_primary_key('cdid');

__PACKAGE__->belongs_to('artist' => 'MyApp::Schema::Result::Artist');
__PACKAGE__->has_many('tracks' => 'MyApp::Schema::Result::Track');

1;

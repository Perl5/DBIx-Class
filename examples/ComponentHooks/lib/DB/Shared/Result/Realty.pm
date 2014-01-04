package DB::Shared::Result::Realty;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('__dummy');

__PACKAGE__->add_columns(qw/ id address /);

__PACKAGE__->set_primary_key('id');

1;

package DB::Shared::Result::Realty::Apartment;

use base qw/DB::Shared::Result::Realty/;

__PACKAGE__->table('__dummy');

__PACKAGE__->add_columns(qw/ square rooms floor /);

1;

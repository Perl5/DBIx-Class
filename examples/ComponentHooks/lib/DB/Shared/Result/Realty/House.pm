package DB::Shared::Result::Realty::House;

use base qw/DB::Shared::Result::Realty/;

__PACKAGE__->table('__dummy');

__PACKAGE__->add_columns(qw/ house_square floors /);

1;

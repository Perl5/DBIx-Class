package DB::Result::Realty::House::Rent;

use base qw/DB::Shared::Result::Realty::House/;

__PACKAGE__->table('house_rent');

__PACKAGE__->load_components('+DB::ResultRole::Realty::Rent');

1;

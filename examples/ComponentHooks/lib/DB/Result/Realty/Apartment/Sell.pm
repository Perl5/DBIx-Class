package DB::Result::Realty::Apartment::Sell;

use base qw/DB::Shared::Result::Realty::Apartment/;

__PACKAGE__->table('apartment_sell');

__PACKAGE__->load_components('+DB::ResultRole::Realty::Sell');

1;

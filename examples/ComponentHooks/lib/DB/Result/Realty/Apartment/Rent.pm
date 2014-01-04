package DB::Result::Realty::Apartment::Rent;

use base qw/DB::Shared::Result::Realty::Apartment/;

__PACKAGE__->table('apartment_rent');

__PACKAGE__->load_components('+DB::ResultRole::Realty::Rent');

1;

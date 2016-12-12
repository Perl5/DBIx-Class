package DB::Result::Realty::Apartment::Rent::Daily;

use base qw/DB::Result::Realty::Apartment::Rent/;

__PACKAGE__->table('apartment_rent_daily');

__PACKAGE__->load_components('+DB::ResultRole::Realty::Rent::Daily');

1;

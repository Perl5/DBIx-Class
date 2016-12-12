package DB::Result::Realty::House::Sell;

use base qw/DB::Shared::Result::Realty::House/;

__PACKAGE__->table('house_sell');

__PACKAGE__->load_components('+DB::ResultRole::Realty::Sell');

1;

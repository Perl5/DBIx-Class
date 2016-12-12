package DB::ResultRole::Realty::Rent;

use base qw/DBIx::Class::Core/;

use Class::C3::Componentised::ApplyHooks
    -after_apply => sub {
        my ($class, $component) = @_;

        $class->add_columns(qw/ min_rent_period price_per_month /);
    };
1;

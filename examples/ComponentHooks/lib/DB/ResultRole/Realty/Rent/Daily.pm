package DB::ResultRole::Realty::Rent::Daily;

use base qw/DBIx::Class::Core/;

use Class::C3::Componentised::ApplyHooks
    -after_apply => sub {
        my ($class, $component) = @_;

        $class->add_columns(qw/ checkout_time price_per_day /);
        $class->remove_columns(qw/ price_per_month /);
    };
1;

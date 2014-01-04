package DB::ResultRole::Realty::Sell;

use base qw/DBIx::Class::Core/;

use Class::C3::Componentised::ApplyHooks
    -after_apply => sub {
        my ($class, $component) = @_;

        $class->add_columns(qw/ price_per_meter /);
    };

1;

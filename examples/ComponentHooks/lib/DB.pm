package DB;

use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_namespaces;

__PACKAGE__->load_classes(
    {
        'DB::Shared::Result' =>
            [ 'Realty', 'Realty::Apartment', 'Realty::House', ]
    }
);

1;

package DBIx::Class::UUIDMaker::APR::UUID;
use base qw/DBIx::Class::UUIDMaker/;
use APR::UUID ();

sub as_string {
    return APR::UUID->new->format;
};

1;

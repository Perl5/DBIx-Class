package DBIx::Class::UUIDMaker::Data::Uniqid;
use base qw/DBIx::Class::UUIDMaker/;
use Data::Uniqid ();

sub as_string {
    return Data::Uniqid->luniqid;
};

1;

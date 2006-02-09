package DBIx::Class::UUIDMaker::Data::UUID;
use base qw/DBIx::Class::UUIDMaker/;
use Data::UUID ();

sub as_string {
    return Data::UUID->new->to_string(Data::UUID->new->create);
};

1;

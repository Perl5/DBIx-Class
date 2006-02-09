package DBIx::Class::UUIDMaker::UUID;
use base qw/DBIx::Class::UUIDMaker/;
use UUID ();

sub as_string {
    my ($uuid, $uuidstring);
    UUID::generate($uuid);
    UUID::unparse($uuid, $uuidstring);

    return $uuidstring;
};

1;

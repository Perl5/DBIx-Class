package DBIx::Class::UUIDMaker::Win32API::GUID;
use base qw/DBIx::Class::UUIDMaker/;
use Win32API::GUID ();

sub as_string {
    return Win32API::GUID::CreateGuid();
};

1;

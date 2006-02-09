package DBIx::Class::UUIDMaker::Win32::Guidgen;
use base qw/DBIx::Class::UUIDMaker/;
use Win32::Guidgen ();

sub as_string {
    my $uuid = Win32::Guidgen::create();
    $uuid =~ s/(^\{|\}$)//;

    return $uuid;
};

1;

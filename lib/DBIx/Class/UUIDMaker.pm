package DBIx::Class::UUIDMaker;

sub new {
    return bless {}, shift;
};

sub as_string {
    return undef;
};

1;

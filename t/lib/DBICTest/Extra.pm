package # hide from PAUSE 
    DBICTest::Extra;
use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes("Foo");

1;

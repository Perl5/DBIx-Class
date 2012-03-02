package # hide from PAUSE
    DBICTest::ResultSetManager;
use base 'DBIx::Class::Schema';

__PACKAGE__->lazy_load_classes("Foo");

1;

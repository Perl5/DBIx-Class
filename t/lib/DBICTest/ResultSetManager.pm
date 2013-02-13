package # hide from PAUSE
    DBICTest::ResultSetManager;

use warnings;
use strict;

use base 'DBICTest::BaseSchema';

__PACKAGE__->load_classes("Foo");

1;

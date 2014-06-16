package # hide from PAUSE
    DBICTest::Taint::Classes::Manual;

use warnings;
use strict;

use base 'DBIx::Class::Core';
__PACKAGE__->table('test');

1;

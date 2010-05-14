package Foo;
use base 'DBIx::Class::Schema';

our $loaded = 1;
our $deploy = 0;
sub connect { bless {}, 'Foo' }
sub deploy {$deploy = 1}

1;

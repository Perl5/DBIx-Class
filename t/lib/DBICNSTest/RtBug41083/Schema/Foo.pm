package DBICNSTest::RtBug41083::Schema::Foo;
use strict;
use warnings;
use base 'DBIx::Class';
__PACKAGE__->load_components('Core');
__PACKAGE__->table('foo');
__PACKAGE__->add_columns('foo');
1;

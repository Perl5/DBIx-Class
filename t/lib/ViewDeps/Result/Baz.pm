package    # hide from PAUSE
    ViewDeps::Result::Baz;
## Used in 105view_deps.t

use strict;
use warnings;
use base qw(DBIx::Class::Core);

__PACKAGE__->table('bar');

__PACKAGE__->add_columns( id => { data_type => 'integer' } );

__PACKAGE__->belongs_to(
    'table',
    'ViewDeps::Result::JustATable',
    { 'foreign.id' => 'self.b' },
);

__PACKAGE__->has_many( 'foos', 'ViewDeps::Result::Foo',
    { 'foreign.a' => 'self.id' } );

1;

package    # hide from PAUSE
    ViewDeps::Result::Bar;

use strict;
use warnings;
use base qw/ViewDeps::Result::Foo/;

require ViewDeps::Result::Mixin;

__PACKAGE__->table('bar');

__PACKAGE__->result_source_instance->deploy_depends_on(
    ["ViewDeps::Result::Mixin", "ViewDeps::Result::Baz"] );

__PACKAGE__->add_columns( b => { data_type => 'integer' } );

__PACKAGE__->belongs_to(
    'table',
    'ViewDeps::Result::JustATable',
    { 'foreign.id' => 'self.b' },
);

__PACKAGE__->has_many( 'foos', 'ViewDeps::Result::Foo',
    { 'foreign.id' => 'self.id' } );

1;

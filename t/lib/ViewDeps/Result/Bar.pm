package # hide from PAUSE
    ViewDeps::Result::Bar;

use strict;
use warnings;
use parent qw(ViewDeps::Result::Foo);

require ViewDeps::Result::Mixin;

__PACKAGE__->table('bar');

__PACKAGE__->result_source_instance->depends_on(
    {  ViewDeps::Result::Mixin->result_source_instance->name => 1 }
);

__PACKAGE__->add_columns(
  b => { data_type => 'integer' }
);

__PACKAGE__->belongs_to(
  'b_thang',
  'ViewDeps::Result::JustATable',
  { 'foreign.id' => 'self.b' },
);

__PACKAGE__->has_many(
  'foos',
  'ViewDeps::Result::Foo',
  { 'foreign.a' => 'self.id' }
);

1;

package # hide from PAUSE
    ViewDeps::Result::Bar;

use strict;
use warnings;
use base qw(ViewDeps::Result::Foo);

use ViewDeps::Result::Mixin;
use ViewDeps::Result::Baz;

__PACKAGE__->table('bar');

__PACKAGE__->result_source_instance->deploy_depends_on(
 "ViewDeps::Result::Baz", "ViewDeps::Result::Mixin"  
);

__PACKAGE__->add_columns(
  b => { data_type => 'integer' }
);

__PACKAGE__->belongs_to(
  'table',
  'ViewDeps::Result::JustATable',
  { 'foreign.id' => 'self.b' },
);

__PACKAGE__->has_many(
  'foos',
  'ViewDeps::Result::Foo',
  { 'foreign.id' => 'self.id' }
);

1;

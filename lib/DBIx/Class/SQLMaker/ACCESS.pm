package # Hide from PAUSE
  DBIx::Class::SQLMaker::ACCESS;

use strict;
use warnings;
use Module::Runtime ();
use base 'DBIx::Class::SQLMaker';

sub _build_base_renderer_class {
  Module::Runtime::use_module('DBIx::Class::SQLMaker::Renderer::Access');
}

1;

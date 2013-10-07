package # Hide from PAUSE
  DBIx::Class::SQLMaker::SQLite;

use base qw( DBIx::Class::SQLMaker );

#sub _build_renderer_class {
#  Module::Runtime::use_module('Data::Query::Renderer::SQL::SQLite')
#}

#
# SQLite does not understand SELECT ... FOR UPDATE
# Disable it here
sub _lock_select { '' };

1;

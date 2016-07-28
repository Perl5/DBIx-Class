package MyApp::Schema;

use warnings;
use strict;

use base qw/DBIx::Class::Schema/;
__PACKAGE__->load_namespaces;

# no point taxing 5.8, but otherwise leave the default: a user may
# be interested in exploring and seeing what broke
__PACKAGE__->schema_sanity_checker('')
  if DBIx::Class::_ENV_::OLD_MRO;

1;

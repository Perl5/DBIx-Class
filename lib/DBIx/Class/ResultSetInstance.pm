package DBIx::Class::ResultSetInstance;

use base qw/DBIx::Class/;

sub search         { shift->resultset_instance->search(@_);         }
sub search_literal { shift->resultset_instance->search_literal(@_); }
sub count          { shift->resultset_instance->count(@_);          }
sub count_literal  { shift->resultset_instance->count_literal(@_);  }

__PACKAGE__->mk_classdata('resultset_instance');

1;

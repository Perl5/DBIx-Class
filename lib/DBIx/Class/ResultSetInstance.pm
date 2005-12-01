package DBIx::Class::ResultSetInstance;

use base qw/DBIx::Class/;

sub search         { shift->resultset->search(@_);         }
sub search_literal { shift->resultset->search_literal(@_); }
sub count          { shift->resultset->count(@_);          }
sub count_literal  { shift->resultset->count_literal(@_);  }

1;

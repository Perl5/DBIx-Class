package DBIx::Class::ResultSetInstance;

use base qw/DBIx::Class/;

sub search { shift->resultset->search(@_); }

1;

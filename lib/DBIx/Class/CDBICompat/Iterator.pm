package DBIx::Class::CDBICompat::Iterator;

use strict;
use warnings;

sub _init_result_source_instance {
  my $class = shift;
  
  my $table = $class->next::method(@_);
  $table->resultset_class("DBIx::Class::CDBICompat::Iterator::ResultSet");

  return $table;
}



package DBIx::Class::CDBICompat::Iterator::ResultSet;

use strict;
use warnings;

use base qw(DBIx::Class::ResultSet);

sub _bool {
  return $_[0]->count;
}

1;

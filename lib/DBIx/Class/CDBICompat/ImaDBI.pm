package DBIx::Class::CDBICompat::ImaDBI;

use strict;
use warnings;

use NEXT;

sub db_Main {
  return $_[0]->_get_dbh;
}

sub _dbi_connect {
  my ($class, @info) = @_;
  $info[3] = { %{ $info[3] || {}} };
  $info[3]->{RootClass} = 'DBIx::ContextualFetch';
  return $class->NEXT::_dbi_connect(@info);
}

sub __driver {
  return $_[0]->_get_dbh->{Driver}->{Name};
}

1;

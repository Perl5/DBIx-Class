package DBIx::Class::Storage::DBI::Sybase::NoBindVars;

use base qw/
  DBIx::Class::Storage::DBI::NoBindVars
  DBIx::Class::Storage::DBI::Sybase
/;

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;

  # @@identity works only if not using placeholders
  # Should this query be cached?
  return ($dbh->selectrow_array('select @@identity'))[0];
}

1;

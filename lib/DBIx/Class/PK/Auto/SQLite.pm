package DBIx::Class::PK::Auto::SQLite;

use strict;
use warnings;

sub _last_insert_id {
  return $_[0]->_get_dbh->func('last_insert_rowid');
}

1;

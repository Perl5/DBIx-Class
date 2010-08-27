package # Hide from PAUSE
  DBIx::Class::SQLMaker::MSSQL;

use base qw( DBIx::Class::SQLMaker );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

#
# MSSQL does not support ... OVER() ... RNO limits
#
sub _rno_default_order {
  return \ '(SELECT(1))';
}

1;

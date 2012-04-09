package # Hide from PAUSE
  DBIx::Class::SQLMaker::MSSQL;

use base qw( DBIx::Class::SQLMaker );

# a + b + c + d concatenation style
sub _concat { join(' + ', @{$_[1]}); }

#
# MSSQL does not support ... OVER() ... RNO limits
#
sub _rno_default_order {
  return \ '(SELECT(1))';
}

1;

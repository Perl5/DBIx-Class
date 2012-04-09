package # Hide from PAUSE
  DBIx::Class::SQLMaker::PostgreSQL;

use base qw( DBIx::Class::SQLMaker );

###################################################
### FIXME: This only works in PostgreSQL 9.2!!! ###
###################################################
### Need assistance on how best to split up based on normalized_dbms_version (OracleJoin method, _determine_* function, etc.)

# CONCAT(a, b, c, d) style
# Also, PostgreSQL has its own CONCAT_WS function (hence the use of $op)
sub _concat {
  my ($self, $op, $strs) = @_;
  (@$strs > 1) ? $_[0]->_sqlcase($op).'('.join(', ', @$strs).')' : $strs->[0];
}

# this is now a simple pass function
sub _where_op_CONCAT_WS {
  my $self = shift;
  return $self->_where_op_CONCAT(@_);
}

1;

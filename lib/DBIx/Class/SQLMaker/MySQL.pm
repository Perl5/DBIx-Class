package # Hide from PAUSE
  DBIx::Class::SQLMaker::MySQL;

use base qw( DBIx::Class::SQLMaker );

# CONCAT(a, b, c, d) style
# Also, MySQL has its own CONCAT_WS function (hence the use of $op)
sub _concat {
  my ($self, $op, $strs) = @_;
  (@$strs > 1) ? $_[0]->_sqlcase($op).'('.join(', ', @$strs).')' : $strs->[0];
}

# this is now a simple pass function
sub _where_op_CONCAT_WS {
  my $self = shift;
  return $self->_where_op_CONCAT(@_);
}

#
# MySQL does not understand the standard INSERT INTO $table DEFAULT VALUES
# Adjust SQL here instead
#
sub insert {
  my $self = shift;

  if (! $_[1] or (ref $_[1] eq 'HASH' and !keys %{$_[1]} ) ) {
    my $table = $self->_quote($_[0]);
    return "INSERT INTO ${table} () VALUES ()"
  }

  return $self->next::method (@_);
}

# Allow STRAIGHT_JOIN's
sub _generate_join_clause {
    my ($self, $join_type) = @_;

    if( $join_type && $join_type =~ /^STRAIGHT\z/i ) {
        return ' STRAIGHT_JOIN '
    }

    return $self->next::method($join_type);
}

# LOCK IN SHARE MODE
my $for_syntax = {
   update => 'FOR UPDATE',
   shared => 'LOCK IN SHARE MODE'
};

sub _lock_select {
   my ($self, $type) = @_;

   my $sql = $for_syntax->{$type}
    || $self->throw_exception("Unknown SELECT .. FOR type '$type' requested");

   return " $sql";
}

1;

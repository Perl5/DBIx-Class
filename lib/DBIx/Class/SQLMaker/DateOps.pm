package DBIx::Class::SQLMaker::DateOps;

use base qw/
  Class::Accessor::Grouped
/;
__PACKAGE__->mk_group_accessors (simple => qw/datetime_parser/);
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract|^Try::Tiny/;
use Sub::Name 'subname';

sub _where_op_CONVERT_DATETIME {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;
  croak "-$op takes a DateTime only" unless ref $rhs  && $rhs->isa('DateTime');

  # in case we are called as a top level special op (no '=')
  my $lhs = shift;

  $rhs = $self->datetime_parser->format_datetime($rhs);

  my @bind = [
    ($lhs || $self->{_nested_func_lhs} || undef),
    $rhs
  ];

  return $lhs
    ? (
      $self->_convert($self->_quote($lhs)) . ' = ' . $self->_convert('?'),
      @bind
    )
    : (
      $self->_convert('?'),
      @bind
    )
  ;
}

sub _unsupported_date_extraction {
   "date part extraction not supported for part \"$_[1]\" with database \"$_[2]\""
}

sub _unsupported_date_adding {
   "date part adding not supported for part \"$_[1]\" with database \"$_[2]\""
}

sub _unsupported_date_diff {
   "date diff not supported for part \"$_[1]\" with database \"$_[2]\""
}

sub _datetime_sql { die 'date part extraction not implemented for this database' }

sub _datetime_diff_sql { die 'date diffing not implemented for this database' }
sub _datetime_add_sql { die 'date adding not implemented for this database' }

sub _where_op_GET_DATETIME {
  my ($self) = @_;

  my ($k, $op, $vals);

  if (@_ == 3) {
     $op = $_[1];
     $vals = $_[2];
     $k = '';
  } elsif (@_ == 4) {
     $k = $_[1];
     $op = $_[2];
     $vals = $_[3];
  }

  croak 'args to -dt_get must be an arrayref' unless ref $vals eq 'ARRAY';
  croak 'first arg to -dt_get must be a scalar' unless !ref $vals->[0];

  my $part = $vals->[0];
  my $val  = $vals->[1];

  my ($sql, @bind) = $self->_SWITCH_refkind($val, {
     SCALAR => sub {
       return ($self->_convert('?'), $self->_bindtype($k, $val) );
     },
     SCALARREF => sub {
       return $$val;
     },
     ARRAYREFREF => sub {
       my ($sql, @bind) = @$$val;
       $self->_assert_bindval_matches_bindtype(@bind);
       return ($sql, @bind);
     },
     HASHREF => sub {
       my $method = $self->_METHOD_FOR_refkind("_where_hashpair", $val);
       $self->$method('', $val);
     }
  });

  return $self->_datetime_sql($part, $sql), @bind;
}

for my $part (qw(month year hour minute second)) {
   no strict 'refs';
   my $name = '_where_op_GET_DATETIME_' . uc($part);
   *{$name} = subname "DBIx::Class::SQLMaker::DateOps::$name", sub {
     my $self = shift;
     my ($op, $rhs) = splice @_, -2;

     my $lhs = shift;

     return $self->_where_op_GET_DATETIME($op, $lhs, [$part, $rhs])
   }
}

sub _where_op_GET_DATETIME_DAY {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;

  my $lhs = shift;

  return $self->_where_op_GET_DATETIME($op, $lhs, [day_of_month => $rhs])
}

sub _where_op_DATETIME_NOW {
  my ($self) = @_;

  my ($k, $op, $vals);

  if (@_ == 3) {
     $op = $_[1];
     $vals = $_[2];
     $k = '';
  } elsif (@_ == 4) {
     $k = $_[1];
     $op = $_[2];
     $vals = $_[3];
  }

  croak "args to -$op must be an arrayref" unless ref $vals eq 'ARRAY';
  if (!exists $vals->[0]) {
     return $self->_datetime_now_sql()
  } elsif ($vals->[0] eq 'system') {
     require DateTime;
     return $self->_where_op_CONVERT_DATETIME('dt', DateTime->now);
  } else {
     croak "first arg to -$op must be a 'system' or non-existant"
  }
}

sub _reorder_add_datetime_vars {
   my ($self, $amount, $date) = @_;

   return ($amount, $date);
}

sub _where_op_ADD_DATETIME {
  my ($self) = @_;

  my ($k, $op, $vals);

  if (@_ == 3) {
     $op = $_[1];
     $vals = $_[2];
     $k = '';
  } elsif (@_ == 4) {
     $k = $_[1];
     $op = $_[2];
     $vals = $_[3];
  }

  croak "args to -$op must be an arrayref" unless ref $vals eq 'ARRAY';
  croak "first arg to -$op must be a scalar" unless !ref $vals->[0];
  croak "-$op must have two more arguments" unless scalar @$vals == 3;

  my ($part, @rest) = @$vals;

  my $placeholder = $self->_convert('?');

  my (@all_sql, @all_bind);
  foreach my $val ($self->_reorder_add_datetime_vars(@rest)) {
    my ($sql, @bind) = $self->_SWITCH_refkind($val, {
       SCALAR => sub {
         return ($placeholder, $self->_bindtype($k, $val) );
       },
       SCALARREF => sub {
         return $$val;
       },
       ARRAYREFREF => sub {
         my ($sql, @bind) = @$$val;
         $self->_assert_bindval_matches_bindtype(@bind);
         return ($sql, @bind);
       },
       HASHREF => sub {
         my $method = $self->_METHOD_FOR_refkind("_where_hashpair", $val);
         $self->$method('', $val);
       }
    });
    push @all_sql, $sql;
    push @all_bind, @bind;
  }

  return $self->_datetime_add_sql($part, $all_sql[0], $all_sql[1]), @all_bind
}

sub _where_op_DIFF_DATETIME {
  my ($self) = @_;

  my ($k, $op, $vals);

  if (@_ == 3) {
     $op = $_[1];
     $vals = $_[2];
     $k = '';
  } elsif (@_ == 4) {
     $k = $_[1];
     $op = $_[2];
     $vals = $_[3];
  }

  croak 'args to -dt_diff must be an arrayref' unless ref $vals eq 'ARRAY';
  croak 'first arg to -dt_diff must be a scalar' unless !ref $vals->[0];
  croak '-dt_diff must have two more arguments' unless scalar @$vals == 3;

  my ($part, @val) = @$vals;
  my $placeholder = $self->_convert('?');

  my (@all_sql, @all_bind);
  foreach my $val (@val) {
    my ($sql, @bind) = $self->_SWITCH_refkind($val, {
       SCALAR => sub {
         return ($placeholder, $self->_bindtype($k, $val) );
       },
       SCALARREF => sub {
         return $$val;
       },
       ARRAYREFREF => sub {
         my ($sql, @bind) = @$$val;
         $self->_assert_bindval_matches_bindtype(@bind);
         return ($sql, @bind);
       },
       HASHREF => sub {
         my $method = $self->_METHOD_FOR_refkind("_where_hashpair", $val);
         $self->$method('', $val);
       }
    });
    push @all_sql, $sql;
    push @all_bind, @bind;
  }

  return $self->_datetime_diff_sql($part, $all_sql[0], $all_sql[1]), @all_bind
}

1;

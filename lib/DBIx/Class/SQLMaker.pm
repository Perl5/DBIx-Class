package DBIx::Class::SQLMaker;

use strict;
use warnings;

=head1 NAME

DBIx::Class::SQLMaker - An SQL::Abstract-based SQL maker class

=head1 DESCRIPTION

This module is a subclass of L<SQL::Abstract> and includes a number of
DBIC-specific workarounds, not yet suitable for inclusion into the
L<SQL::Abstract> core. It also provides all (and more than) the functionality
of L<SQL::Abstract::Limit>, see L<DBIx::Class::SQLMaker::LimitDialects> for
more info.

Currently the enhancements to L<SQL::Abstract> are:

=over

=item * Support for C<JOIN> statements (via extended C<table/from> support)

=item * Support of functions in C<SELECT> lists

=item * C<GROUP BY>/C<HAVING> support (via extensions to the order_by parameter)

=item * Support of C<...FOR UPDATE> type of select statement modifiers

=item * The L</-ident> operator

=item * The L</-value> operator

=item * Date Functions:

Note that for the following functions use different functions for different
RDBMS'.  See the SQLMaker docs for your database to see what functions are
used.

=over

=item * -dt => $date_time_obj

This function will convert the passed datetime to whatever format the current
database prefers

=item * -dt_diff => [$unit, \'foo.date_from', \'foo.date_to']

This function will diff two dates and return the units requested. Note that
it correctly recurses if you pass it something like a function or a date value.
Also note that not all RDBMS' are equal; some units supported on some databases
and some are supported on others.  See the documentation for the SQLMaker class
for your database.

=item * -dt_get => [$part, \'foo.date_col']

This function will extract the passed part from the passed column.  Note that
it correctly recurses if you pass it something like a function or a date value.
Also note that not all RDBMS' are equal; some parts supported on some databases
and some are supported on others.  See the documentation for the SQLMaker class
for your database.

=item * -dt_year => \'foo.date_col'

A shortcut for -dt_get => [year => ...]

=item * -dt_month => \'foo.date_col'

A shortcut for -dt_get => [month => ...]

=item * -dt_day => \'foo.date_col'

A shortcut for -dt_get => [day_of_month => ...]

=item * -dt_hour => \'foo.date_col'

A shortcut for -dt_get => [hour => ...]

=item * -dt_minute => \'foo.date_col'

A shortcut for -dt_get => [minute => ...]

=item * -dt_second => \'foo.date_col'

A shortcut for -dt_get => [second => ...]

=back

=back

Another operator is C<-func> that allows you to call SQL functions with
arguments. It receives an array reference containing the function name
as the 0th argument and the other arguments being its parameters. For example:

    my %where = {
      -func => ['substr', 'Hello', 50, 5],
    };

Would give you:

   $stmt = "WHERE (substr(?,?,?))";
   @bind = ("Hello", 50, 5);

Yet another operator is C<-op> that allows you to use SQL operators. It
receives an array reference containing the operator 0th argument and the other
arguments being its operands. For example:

    my %where = {
      foo => { -op => ['+', \'bar', 50, 5] },
    };

Would give you:

   $stmt = "WHERE (foo = bar + ? + ?)";
   @bind = (50, 5);

=cut

use base qw/
  DBIx::Class::SQLMaker::LimitDialects
  SQL::Abstract
  DBIx::Class
/;
use mro 'c3';

use Sub::Name 'subname';
use DBIx::Class::Carp;
use DBIx::Class::Exception;
use namespace::clean;

__PACKAGE__->mk_group_accessors (simple => qw/quote_char name_sep limit_dialect datetime_parser/);

# for when I need a normalized l/r pair
sub _quote_chars {
  map
    { defined $_ ? $_ : '' }
    ( ref $_[0]->{quote_char} ? (@{$_[0]->{quote_char}}) : ( ($_[0]->{quote_char}) x 2 ) )
  ;
}

# FIXME when we bring in the storage weaklink, check its schema
# weaklink and channel through $schema->throw_exception
sub throw_exception { DBIx::Class::Exception->throw($_[1]) }

BEGIN {
  # reinstall the belch()/puke() functions of SQL::Abstract with custom versions
  # that use DBIx::Class::Carp/DBIx::Class::Exception instead of plain Carp
  no warnings qw/redefine/;

  *SQL::Abstract::belch = subname 'SQL::Abstract::belch' => sub (@) {
    my($func) = (caller(1))[3];
    carp "[$func] Warning: ", @_;
  };

  *SQL::Abstract::puke = subname 'SQL::Abstract::puke' => sub (@) {
    my($func) = (caller(1))[3];
    __PACKAGE__->throw_exception("[$func] Fatal: " . join ('',  @_));
  };

  # Current SQLA pollutes its namespace - clean for the time being
  namespace::clean->clean_subroutines(qw/SQL::Abstract carp croak confess/);
}

# the "oh noes offset/top without limit" constant
# limited to 31 bits for sanity (and consistency,
# since it may be handed to the like of sprintf %u)
#
# Also *some* builds of SQLite fail the test
#   some_column BETWEEN ? AND ?: 1, 4294967295
# with the proper integer bind attrs
#
# Implemented as a method, since ::Storage::DBI also
# refers to it (i.e. for the case of software_limit or
# as the value to abuse with MSSQL ordered subqueries)
sub __max_int () { 0x7FFFFFFF };

# poor man's de-qualifier
sub _quote {
  $_[0]->next::method( ( $_[0]{_dequalify_idents} and ! ref $_[1] )
    ? $_[1] =~ / ([^\.]+) $ /x
    : $_[1]
  );
}

sub new {
  my $self = shift->next::method(@_);

  # use the same coderefs, they are prepared to handle both cases
  my @extra_dbic_syntax = (
    { regex => qr/^ ident $/xi, handler => '_where_op_IDENT' },
    { regex => qr/^ value $/xi, handler => '_where_op_VALUE' },
    { regex => qr/^ func  $/ix, handler => '_where_op_FUNC'  },
    { regex => qr/^ op    $/ix, handler => '_where_op_OP'    },
    { regex => qr/^ dt    $/xi, handler => '_where_op_CONVERT_DATETIME' },
    { regex => qr/^ dt_get $/xi, handler => '_where_op_GET_DATETIME' },
    { regex => qr/^ dt_diff $/xi, handler => '_where_op_DIFF_DATETIME' },
    map +{ regex => qr/^ dt_$_ $/xi, handler => '_where_op_GET_DATETIME_'.uc($_) },
      qw(year month day)
  );

  push @{$self->{special_ops}}, @extra_dbic_syntax;
  push @{$self->{unary_ops}}, @extra_dbic_syntax;

  $self;
}

sub _where_op_IDENT {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;
  if (ref $rhs) {
    $self->throw_exception("-$op takes a single scalar argument (a quotable identifier)");
  }

  # in case we are called as a top level special op (no '=')
  my $lhs = shift;

  $_ = $self->_convert($self->_quote($_)) for ($lhs, $rhs);

  return $lhs
    ? "$lhs = $rhs"
    : $rhs
  ;
}

sub _where_op_CONVERT_DATETIME {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;
  croak "-$op takes a DateTime only" unless ref $rhs  && $rhs->isa('DateTime');

  # in case we are called as a top level special op (no '=')
  my $lhs = shift;

  $rhs = $self->datetime_parser->format_datetime($rhs);

  my @bind = [
    ($lhs || $self->{_nested_func_lhs} || croak "Unable to find bindtype for -value $rhs"),
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

sub _unsupported_date_diff {
   "date diff not supported for part \"$_[1]\" with database \"$_[2]\""
}

sub _datetime_sql { die 'date part extraction not implemented for this database' }

sub _datetime_diff_sql { die 'date diffing not implemented for this database' }

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

for my $part (qw(month day year)) {
   no strict 'refs';
   my $name = '_where_op_GET_DATETIME_' . uc($part);
   *{$name} = subname "DBIx::Class::SQLMaker::$name", sub {
     my $self = shift;
     my ($op, $rhs) = splice @_, -2;

     my $lhs = shift;

     return $self->_where_op_GET_DATETIME($op, $lhs, [$part, $rhs])
   }
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

sub _where_op_VALUE {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;

  # in case we are called as a top level special op (no '=')
  my $lhs = shift;

  my @bind = [
    ($lhs || $self->{_nested_func_lhs} || $self->throw_exception("Unable to find bindtype for -value $rhs") ),
    $rhs
  ];

  return $lhs
    ? (
      $self->_convert($self->_quote($lhs)) . ' = ' . $self->_convert('?'),
      @bind
    )
    : (
      $self->_convert('?'),
      @bind,
    )
  ;
}

sub _where_op_NEST {
  carp_unique ("-nest in search conditions is deprecated, you most probably wanted:\n"
      .q|{..., -and => [ \%cond0, \@cond1, \'cond2', \[ 'cond3', [ col => bind ] ], etc. ], ... }|
  );

  shift->next::method(@_);
}

# Handle limit-dialect selection
sub select {
  my ($self, $table, $fields, $where, $rs_attrs, $limit, $offset) = @_;


  $fields = $self->_recurse_fields($fields);

  if (defined $offset) {
    $self->throw_exception('A supplied offset must be a non-negative integer')
      if ( $offset =~ /\D/ or $offset < 0 );
  }
  $offset ||= 0;

  if (defined $limit) {
    $self->throw_exception('A supplied limit must be a positive integer')
      if ( $limit =~ /\D/ or $limit <= 0 );
  }
  elsif ($offset) {
    $limit = $self->__max_int;
  }


  my ($sql, @bind);
  if ($limit) {
    # this is legacy code-flow from SQLA::Limit, it is not set in stone

    ($sql, @bind) = $self->next::method ($table, $fields, $where);

    my $limiter =
      $self->can ('emulate_limit')  # also backcompat hook from SQLA::Limit
        ||
      do {
        my $dialect = $self->limit_dialect
          or $self->throw_exception( "Unable to generate SQL-limit - no limit dialect specified on $self, and no emulate_limit method found" );
        $self->can ("_$dialect")
          or $self->throw_exception(__PACKAGE__ . " does not implement the requested dialect '$dialect'");
      }
    ;

    $sql = $self->$limiter (
      $sql,
      { %{$rs_attrs||{}}, _selector_sql => $fields },
      $limit,
      $offset
    );
  }
  else {
    ($sql, @bind) = $self->next::method ($table, $fields, $where, $rs_attrs);
  }

  push @{$self->{where_bind}}, @bind;

# this *must* be called, otherwise extra binds will remain in the sql-maker
  my @all_bind = $self->_assemble_binds;

  $sql .= $self->_lock_select ($rs_attrs->{for})
    if $rs_attrs->{for};

  return wantarray ? ($sql, @all_bind) : $sql;
}

sub _assemble_binds {
  my $self = shift;
  return map { @{ (delete $self->{"${_}_bind"}) || [] } } (qw/select from where group having order limit/);
}

my $for_syntax = {
  update => 'FOR UPDATE',
  shared => 'FOR SHARE',
};
sub _lock_select {
  my ($self, $type) = @_;
  my $sql = $for_syntax->{$type} || $self->throw_exception( "Unknown SELECT .. FOR type '$type' requested" );
  return " $sql";
}

# Handle default inserts
sub insert {
# optimized due to hotttnesss
#  my ($self, $table, $data, $options) = @_;

  # SQLA will emit INSERT INTO $table ( ) VALUES ( )
  # which is sadly understood only by MySQL. Change default behavior here,
  # until SQLA2 comes with proper dialect support
  if (! $_[2] or (ref $_[2] eq 'HASH' and !keys %{$_[2]} ) ) {
    my @bind;
    my $sql = sprintf(
      'INSERT INTO %s DEFAULT VALUES', $_[0]->_quote($_[1])
    );

    if ( ($_[3]||{})->{returning} ) {
      my $s;
      ($s, @bind) = $_[0]->_insert_returning ($_[3]);
      $sql .= $s;
    }

    return ($sql, @bind);
  }

  next::method(@_);
}

sub _recurse_fields {
  my ($self, $fields, $depth) = @_;
  $depth ||= 0;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    return join(', ', map { $self->_recurse_fields($_, $depth + 1) } @$fields)
      if $depth != 1;

    my ($sql, @bind) = $self->_recurse_where({@$fields});

    push @{$self->{select_bind}}, @bind;
    return $sql;
  }
  elsif ($ref eq 'HASH') {
    my %hash = %$fields;  # shallow copy

    my $as = delete $hash{-as};   # if supplied

    my ($func, $args, @toomany) = %hash;

    # there should be only one pair
    if (@toomany) {
      $self->throw_exception( "Malformed select argument - too many keys in hash: " . join (',', keys %$fields ) );
    }

    if (lc ($func) eq 'distinct' && ref $args eq 'ARRAY' && @$args > 1) {
      $self->throw_exception (
        'The select => { distinct => ... } syntax is not supported for multiple columns.'
       .' Instead please use { group_by => [ qw/' . (join ' ', @$args) . '/ ] }'
       .' or { select => [ qw/' . (join ' ', @$args) . '/ ], distinct => 1 }'
      );
    }

    my $select = sprintf ('%s( %s )%s',
      $self->_sqlcase($func),
      $self->_recurse_fields($args, $depth + 1),
      $as
        ? sprintf (' %s %s', $self->_sqlcase('as'), $self->_quote ($as) )
        : ''
    );

    return $select;
  }
  # Is the second check absolutely necessary?
  elsif ( $ref eq 'REF' and ref($$fields) eq 'ARRAY' ) {
    push @{$self->{select_bind}}, @{$$fields}[1..$#$$fields];
    return $$fields->[0];
  }
  else {
    $self->throw_exception( $ref . qq{ unexpected in _recurse_fields()} );
  }
}


# this used to be a part of _order_by but is broken out for clarity.
# What we have been doing forever is hijacking the $order arg of
# SQLA::select to pass in arbitrary pieces of data (first the group_by,
# then pretty much the entire resultset attr-hash, as more and more
# things in the SQLA space need to have mopre info about the $rs they
# create SQL for. The alternative would be to keep expanding the
# signature of _select with more and more positional parameters, which
# is just gross. All hail SQLA2!
sub _parse_rs_attrs {
  my ($self, $arg) = @_;

  my $sql = '';

  if ($arg->{group_by}) {
    # horible horrible, waiting for refactor
    local $self->{select_bind};
    if (my $g = $self->_recurse_fields($arg->{group_by}) ) {
      $sql .= $self->_sqlcase(' group by ') . $g;
      push @{$self->{group_bind} ||= []}, @{$self->{select_bind}||[]};
    }
  }

  if (defined $arg->{having}) {
    my ($frag, @bind) = $self->_recurse_where($arg->{having});
    push(@{$self->{having_bind}}, @bind);
    $sql .= $self->_sqlcase(' having ') . $frag;
  }

  if (defined $arg->{order_by}) {
    $sql .= $self->_order_by ($arg->{order_by});
  }

  return $sql;
}

sub _order_by {
  my ($self, $arg) = @_;

  # check that we are not called in legacy mode (order_by as 4th argument)
  if (ref $arg eq 'HASH' and not grep { $_ =~ /^-(?:desc|asc)/i } keys %$arg ) {
    return $self->_parse_rs_attrs ($arg);
  }
  else {
    my ($sql, @bind) = $self->next::method($arg);
    push @{$self->{order_bind}}, @bind;
    return $sql;
  }
}

sub _table {
# optimized due to hotttnesss
#  my ($self, $from) = @_;
  if (my $ref = ref $_[1] ) {
    if ($ref eq 'ARRAY') {
      return $_[0]->_recurse_from(@{$_[1]});
    }
    elsif ($ref eq 'HASH') {
      return $_[0]->_recurse_from($_[1]);
    }
    elsif ($ref eq 'REF' && ref ${$_[1]} eq 'ARRAY') {
      my ($sql, @bind) = @{ ${$_[1]} };
      push @{$_[0]->{from_bind}}, @bind;
      return $sql
    }
  }
  return $_[0]->next::method ($_[1]);
}

sub _generate_join_clause {
    my ($self, $join_type) = @_;

    $join_type = $self->{_default_jointype}
      if ! defined $join_type;

    return sprintf ('%s JOIN ',
      $join_type ?  $self->_sqlcase($join_type) : ''
    );
}

sub _where_op_FUNC {
  my ($self) = @_;

  my ($k, $vals);

  if (@_ == 3) {
     # $_[1] gets set to "op"
     $vals = $_[2];
     $k = '';
  } elsif (@_ == 4) {
     $k = $_[1];
     # $_[2] gets set to "op"
     $vals = $_[3];
  }

  my $label       = $self->_convert($self->_quote($k));
  my $placeholder = $self->_convert('?');

  croak '-func must be an array' unless ref $vals eq 'ARRAY';
  croak 'first arg for -func must be a scalar' unless !ref $vals->[0];

  my ($func,@rest_of_vals) = @$vals;

  $self->_assert_pass_injection_guard($func);

  my (@all_sql, @all_bind);
  foreach my $val (@rest_of_vals) {
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

  my ($clause, @bind) = ("$func(" . (join ",", @all_sql) . ")", @all_bind);

  my $sql = $k ? "( $label = $clause )" : "( $clause )";
  return ($sql, @bind)
}

sub _where_op_OP {
  my ($self) = @_;

  my ($k, $vals);

  if (@_ == 3) {
     # $_[1] gets set to "op"
     $vals = $_[2];
     $k = '';
  } elsif (@_ == 4) {
     $k = $_[1];
     # $_[2] gets set to "op"
     $vals = $_[3];
  }

  my $label       = $self->_convert($self->_quote($k));
  my $placeholder = $self->_convert('?');

  croak 'argument to -op must be an arrayref' unless ref $vals eq 'ARRAY';
  croak 'first arg for -op must be a scalar' unless !ref $vals->[0];

  my ($op, @rest_of_vals) = @$vals;

  $self->_assert_pass_injection_guard($op);

  my (@all_sql, @all_bind);
  foreach my $val (@rest_of_vals) {
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

  my ($clause, @bind) = ((join " $op ", @all_sql), @all_bind);

  my $sql = $k ? "( $label = $clause )" : "( $clause )";
  return ($sql, @bind)
}

sub _recurse_from {
  my $self = shift;

  return join (' ', $self->_gen_from_blocks(@_) );
}

sub _gen_from_blocks {
  my ($self, $from, @joins) = @_;

  my @fchunks = $self->_from_chunk_to_sql($from);

  for (@joins) {
    my ($to, $on) = @$_;

    # check whether a join type exists
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    my $join_type;
    if (ref($to_jt) eq 'HASH' and defined($to_jt->{-join_type})) {
      $join_type = $to_jt->{-join_type};
      $join_type =~ s/^\s+ | \s+$//xg;
    }

    my @j = $self->_generate_join_clause( $join_type );

    if (ref $to eq 'ARRAY') {
      push(@j, '(', $self->_recurse_from(@$to), ')');
    }
    else {
      push(@j, $self->_from_chunk_to_sql($to));
    }

    my ($sql, @bind) = $self->_join_condition($on);
    push(@j, ' ON ', $sql);
    push @{$self->{from_bind}}, @bind;

    push @fchunks, join '', @j;
  }

  return @fchunks;
}

sub _from_chunk_to_sql {
  my ($self, $fromspec) = @_;

  return join (' ', $self->_SWITCH_refkind($fromspec, {
    SCALARREF => sub {
      $$fromspec;
    },
    ARRAYREFREF => sub {
      push @{$self->{from_bind}}, @{$$fromspec}[1..$#$$fromspec];
      $$fromspec->[0];
    },
    HASHREF => sub {
      my ($as, $table, $toomuch) = ( map
        { $_ => $fromspec->{$_} }
        ( grep { $_ !~ /^\-/ } keys %$fromspec )
      );

      $self->throw_exception( "Only one table/as pair expected in from-spec but an exra '$toomuch' key present" )
        if defined $toomuch;

      ($self->_from_chunk_to_sql($table), $self->_quote($as) );
    },
    SCALAR => sub {
      $self->_quote($fromspec);
    },
  }));
}

sub _join_condition {
  my ($self, $cond) = @_;

  # Backcompat for the old days when a plain hashref
  # { 't1.col1' => 't2.col2' } meant ON t1.col1 = t2.col2
  # Once things settle we should start warning here so that
  # folks unroll their hacks
  if (
    ref $cond eq 'HASH'
      and
    keys %$cond == 1
      and
    (keys %$cond)[0] =~ /\./
      and
    ! ref ( (values %$cond)[0] )
  ) {
    $cond = { keys %$cond => { -ident => values %$cond } }
  }
  elsif ( ref $cond eq 'ARRAY' ) {
    # do our own ORing so that the hashref-shim above is invoked
    my @parts;
    my @binds;
    foreach my $c (@$cond) {
      my ($sql, @bind) = $self->_join_condition($c);
      push @binds, @bind;
      push @parts, $sql;
    }
    return join(' OR ', @parts), @binds;
  }

  return $self->_recurse_where($cond);
}

1;

=head1 OPERATORS

=head2 -ident

Used to explicitly specify an SQL identifier. Takes a plain string as value
which is then invariably treated as a column name (and is being properly
quoted if quoting has been requested). Most useful for comparison of two
columns:

    my %where = (
        priority => { '<', 2 },
        requestor => { -ident => 'submitter' }
    );

which results in:

    $stmt = 'WHERE "priority" < ? AND "requestor" = "submitter"';
    @bind = ('2');

=head2 -value

The -value operator signals that the argument to the right is a raw bind value.
It will be passed straight to DBI, without invoking any of the SQL::Abstract
condition-parsing logic. This allows you to, for example, pass an array as a
column value for databases that support array datatypes, e.g.:

    my %where = (
        array => { -value => [1, 2, 3] }
    );

which results in:

    $stmt = 'WHERE array = ?';
    @bind = ([1, 2, 3]);

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

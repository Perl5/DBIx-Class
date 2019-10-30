package DBIx::Class::SQLMaker::ClassicExtensions;

use strict;
use warnings;

=head1 NAME

DBIx::Class::SQLMaker::ClassicExtensions - Class containing generic enhancements to SQL::Abstract::Classic

=head1 DESCRIPTION

This module is not intended to be used standalone. Instead it represents
a quasi-role, that one would "mix in" via classic C<@ISA> inheritance into
a DBIx::Class::SQLMaker-like provider. See
L<DBIx::Class::Storage::DBI/connect_call_rebase_sqlmaker> for more info.

Currently the enhancements over L<SQL::Abstract::Classic> are:

=over

=item * Support for C<JOIN> statements (via extended C<table/from> support)

=item * Support of functions in C<SELECT> lists

=item * C<GROUP BY>/C<HAVING> support (via extensions to the order_by parameter)

=item * A rudimentary multicolumn IN operator

=item * Support of C<...FOR UPDATE> type of select statement modifiers

=back

=cut

# to pull in CAG and the frame-boundary-markers
use base 'DBIx::Class';
use DBIx::Class::Carp;
use namespace::clean;

__PACKAGE__->mk_group_accessors (simple => qw/quote_char name_sep limit_dialect/);

sub _quoting_enabled {
  ( defined $_[0]->{quote_char} and length $_[0]->{quote_char} ) ? 1 : 0
}

# for when I need a normalized l/r pair
sub _quote_chars {

  # in case we are called in the old !!$sm->_quote_chars fashion
  return () if !wantarray and ( ! defined $_[0]->{quote_char} or ! length $_[0]->{quote_char} );

  map
    { defined $_ ? $_ : '' }
    ( ref $_[0]->{quote_char} ? (@{$_[0]->{quote_char}}) : ( ($_[0]->{quote_char}) x 2 ) )
  ;
}

# FIXME when we bring in the storage weaklink, check its schema
# weaklink and channel through $schema->throw_exception
sub throw_exception { DBIx::Class::Exception->throw($_[1]) }

sub belch {
  shift;  # throw away $self
  carp( "Warning: ", @_ );
};

sub puke {
  shift->throw_exception("Fatal: " . join ('',  @_));
};

# constants-methods are used not only here, but also in comparison tests
sub __rows_bindtype () {
  +{ sqlt_datatype => 'integer' }
}
sub __offset_bindtype () {
  +{ sqlt_datatype => 'integer' }
}
sub __total_bindtype () {
  +{ sqlt_datatype => 'integer' }
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

# we ne longer need to check this - DBIC has ways of dealing with it
# specifically ::Storage::DBI::_resolve_bindattrs()
sub _assert_bindval_matches_bindtype () { 1 };

# poor man's de-qualifier
sub _quote {
  $_[0]->next::method( ( $_[0]{_dequalify_idents} and ! ref $_[1] )
    ? $_[1] =~ / ([^\.]+) $ /x
    : $_[1]
  );
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


  ($fields, @{$self->{select_bind}}) = $self->_recurse_fields($fields);

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

    my $limiter;

    if( $limiter = $self->can ('emulate_limit') ) {
      carp_unique(
        'Support for the legacy emulate_limit() mechanism inherited from '
      . 'SQL::Abstract::Limit has been deprecated, and will be removed at '
      . 'some future point, as it gets in the way of architectural and/or '
      . 'performance advances within DBIC. If your code uses this type of '
      . 'limit specification please file an RT and provide the source of '
      . 'your emulate_limit() implementation, so an acceptable upgrade-path '
      . 'can be devised'
      );
    }
    else {
      my $dialect = $self->limit_dialect
        or $self->throw_exception( "Unable to generate SQL-limit - no limit dialect specified on $self" );

      $limiter = $self->can ("_$dialect")
        or $self->throw_exception(__PACKAGE__ . " does not implement the requested dialect '$dialect'");
    }

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
  return map { @{ (delete $self->{"${_}_bind"}) || [] } } (qw/pre_select select from where group having order limit/);
}

my $for_syntax = {
  update => 'FOR UPDATE',
  shared => 'FOR SHARE',
};
sub _lock_select {
  my ($self, $type) = @_;

  my $sql;
  if (ref($type) eq 'SCALAR') {
    $sql = "FOR $$type";
  }
  else {
    $sql = $for_syntax->{$type} || $self->throw_exception( "Unknown SELECT .. FOR type '$type' requested" );
  }

  return " $sql";
}

# Handle default inserts
sub insert {
# optimized due to hotttnesss
#  my ($self, $table, $data, $options) = @_;

  # FIXME SQLMaker will emit INSERT INTO $table ( ) VALUES ( )
  # which is sadly understood only by MySQL. Change default behavior here,
  # until we fold the extra pieces into SQLMaker properly
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
  my ($self, $fields) = @_;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    my (@select, @bind);
    for my $field (@$fields) {
      my ($select, @new_bind) = $self->_recurse_fields($field);
      push @select, $select;
      push @bind, @new_bind;
    }
    return (join(', ', @select), @bind);
  }
  elsif ($ref eq 'HASH') {
    my %hash = %$fields;  # shallow copy

    my $as = delete $hash{-as};   # if supplied

    my ($func, $rhs, @toomany) = %hash;

    # there should be only one pair
    if (@toomany) {
      $self->throw_exception( "Malformed select argument - too many keys in hash: " . join (',', keys %$fields ) );
    }

    if (lc ($func) eq 'distinct' && ref $rhs eq 'ARRAY' && @$rhs > 1) {
      $self->throw_exception (
        'The select => { distinct => ... } syntax is not supported for multiple columns.'
       .' Instead please use { group_by => [ qw/' . (join ' ', @$rhs) . '/ ] }'
       .' or { select => [ qw/' . (join ' ', @$rhs) . '/ ], distinct => 1 }'
      );
    }

    my ($rhs_sql, @rhs_bind) = $self->_recurse_fields($rhs);
    my $select = sprintf ('%s( %s )%s',
      $self->_sqlcase($func),
      $rhs_sql,
      $as
        ? sprintf (' %s %s', $self->_sqlcase('as'), $self->_quote ($as) )
        : ''
    );

    return ($select, @rhs_bind);
  }
  elsif ( $ref eq 'REF' and ref($$fields) eq 'ARRAY' ) {
    return @{$$fields};
  }
  else {
    $self->throw_exception( $ref . qq{ unexpected in _recurse_fields()} );
  }
}


# this used to be a part of _order_by but is broken out for clarity.
# What we have been doing forever is hijacking the $order arg of
# SQLAC::select to pass in arbitrary pieces of data (first the group_by,
# then pretty much the entire resultset attr-hash, as more and more
# things in the SQLMaker space need to have more info about the $rs they
# create SQL for. The alternative would be to keep expanding the
# signature of _select with more and more positional parameters, which
# is just gross.
#
# FIXME - this will have to transition out to a subclass when the effort
# of folding the SQL generating machinery into SQLMaker takes place
sub _parse_rs_attrs {
  my ($self, $arg) = @_;

  my $sql = '';

  if ($arg->{group_by}) {
    if ( my ($group_sql, @group_bind) = $self->_recurse_fields($arg->{group_by}) ) {
      $sql .= $self->_sqlcase(' group by ') . $group_sql;
      push @{$self->{group_bind}}, @group_bind;
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

sub _split_order_chunk {
  my ($self, $chunk) = @_;

  # strip off sort modifiers, but always succeed, so $1 gets reset
  $chunk =~ s/ (?: \s+ (ASC|DESC) )? \s* $//ix;

  return (
    $chunk,
    ( $1 and uc($1) eq 'DESC' ) ? 1 : 0,
  );
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

  return join (' ', do {
    if (! ref $fromspec) {
      $self->_quote($fromspec);
    }
    elsif (ref $fromspec eq 'SCALAR') {
      $$fromspec;
    }
    elsif (ref $fromspec eq 'REF' and ref $$fromspec eq 'ARRAY') {
      push @{$self->{from_bind}}, @{$$fromspec}[1..$#$$fromspec];
      $$fromspec->[0];
    }
    elsif (ref $fromspec eq 'HASH') {
      my ($as, $table, $toomuch) = ( map
        { $_ => $fromspec->{$_} }
        ( grep { $_ !~ /^\-/ } keys %$fromspec )
      );

      $self->throw_exception( "Only one table/as pair expected in from-spec but an exra '$toomuch' key present" )
        if defined $toomuch;

      ($self->_from_chunk_to_sql($table), $self->_quote($as) );
    }
    else {
      $self->throw_exception('Unsupported from refkind: ' . ref $fromspec );
    }
  });
}

sub _join_condition {
  my ($self, $cond) = @_;

  # Backcompat for the old days when a plain hashref
  # { 't1.col1' => 't2.col2' } meant ON t1.col1 = t2.col2
  if (
    ref $cond eq 'HASH'
      and
    keys %$cond == 1
      and
    (keys %$cond)[0] =~ /\./
      and
    ! ref ( (values %$cond)[0] )
  ) {
    carp_unique(
      "ResultSet {from} structures with conditions not conforming to the "
    . "SQL::Abstract::Classic syntax are deprecated: you either need to stop "
    . "abusing {from} altogether, or express the condition properly using the "
    . "{ -ident => ... } operator"
    );
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

# !!! EXPERIMENTAL API !!! WILL CHANGE !!!
#
# This is rather odd, but vanilla SQLA* variants do not have support for
# multicolumn-IN expressions
# Currently has only one callsite in ResultSet, body moved into this subclass
# to raise API questions like:
# - how do we convey a list of idents...?
# - can binds reside on lhs?
#
# !!! EXPERIMENTAL API !!! WILL CHANGE !!!
sub _where_op_multicolumn_in {
  my ($self, $lhs, $rhs) = @_;

  if (! ref $lhs or ref $lhs eq 'ARRAY') {
    my (@sql, @bind);
    for (ref $lhs ? @$lhs : $lhs) {
      if (! ref $_) {
        push @sql, $self->_quote($_);
      }
      elsif (ref $_ eq 'SCALAR') {
        push @sql, $$_;
      }
      elsif (ref $_ eq 'REF' and ref $$_ eq 'ARRAY') {
        my ($s, @b) = @$$_;
        push @sql, $s;
        push @bind, @b;
      }
      else {
        $self->throw_exception("ARRAY of @{[ ref $_ ]}es unsupported for multicolumn IN lhs...");
      }
    }
    $lhs = \[ join(', ', @sql), @bind];
  }
  elsif (ref $lhs eq 'SCALAR') {
    $lhs = \[ $$lhs ];
  }
  elsif (ref $lhs eq 'REF' and ref $$lhs eq 'ARRAY' ) {
    # noop
  }
  else {
    $self->throw_exception( ref($lhs) . "es unsupported for multicolumn IN lhs...");
  }

  # is this proper...?
  $rhs = \[ $self->_recurse_where($rhs) ];

  for ($lhs, $rhs) {
    $$_->[0] = "( $$_->[0] )"
      unless $$_->[0] =~ /^ \s* \( .* \) \s* $/xs;
  }

  \[ join( ' IN ', shift @$$lhs, shift @$$rhs ), @$$lhs, @$$rhs ];
}


###
### Code that mostly used to be in DBIC::SQLMaker::LimitDialects
###

sub _LimitOffset {
    my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;
    $sql .= $self->_parse_rs_attrs( $rs_attrs ) . " LIMIT ?";
    push @{$self->{limit_bind}}, [ $self->__rows_bindtype => $rows ];
    if ($offset) {
      $sql .= " OFFSET ?";
      push @{$self->{limit_bind}}, [ $self->__offset_bindtype => $offset ];
    }
    return $sql;
}

sub _LimitXY {
    my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;
    $sql .= $self->_parse_rs_attrs( $rs_attrs ) . " LIMIT ";
    if ($offset) {
      $sql .= '?, ';
      push @{$self->{limit_bind}}, [ $self->__offset_bindtype => $offset ];
    }
    $sql .= '?';
    push @{$self->{limit_bind}}, [ $self->__rows_bindtype => $rows ];

    return $sql;
}

sub _RowNumberOver {
  my ($self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # get selectors, and scan the order_by (if any)
  my $sq_attrs = $self->_subqueried_limit_attrs ( $sql, $rs_attrs );

  # make up an order if none exists
  my $requested_order = (delete $rs_attrs->{order_by}) || $self->_rno_default_order;

  # the order binds (if any) will need to go at the end of the entire inner select
  local $self->{order_bind};
  my $rno_ord = $self->_order_by ($requested_order);
  push @{$self->{select_bind}}, @{$self->{order_bind}};

  # this is the order supplement magic
  my $mid_sel = $sq_attrs->{selection_outer};
  if (my $extra_order_sel = $sq_attrs->{order_supplement}) {
    for my $extra_col (sort
      { $extra_order_sel->{$a} cmp $extra_order_sel->{$b} }
      keys %$extra_order_sel
    ) {
      $sq_attrs->{selection_inner} .= sprintf (', %s AS %s',
        $extra_col,
        $extra_order_sel->{$extra_col},
      );
    }
  }

  # and this is order re-alias magic
  for my $map ($sq_attrs->{order_supplement}, $sq_attrs->{outer_renames}) {
    for my $col (sort { (length $b) <=> (length $a) } keys %{$map||{}} ) {
      my $re_col = quotemeta ($col);
      $rno_ord =~ s/$re_col/$map->{$col}/;
    }
  }

  # whatever is left of the order_by (only where is processed at this point)
  my $group_having = $self->_parse_rs_attrs($rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});
  my $idx_name = $self->_quote ('rno__row__index');

  push @{$self->{limit_bind}}, [ $self->__offset_bindtype => $offset + 1], [ $self->__total_bindtype => $offset + $rows ];

  return <<EOS;

SELECT $sq_attrs->{selection_outer} FROM (
  SELECT $mid_sel, ROW_NUMBER() OVER( $rno_ord ) AS $idx_name FROM (
    SELECT $sq_attrs->{selection_inner} $sq_attrs->{query_leftover}${group_having}
  ) $qalias
) $qalias WHERE $idx_name >= ? AND $idx_name <= ?

EOS

}

# some databases are happy with OVER (), some need OVER (ORDER BY (SELECT (1)) )
sub _rno_default_order {
  return undef;
}

sub _SkipFirst {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  $sql =~ s/^ \s* SELECT \s+ //ix
    or $self->throw_exception("Unrecognizable SELECT: $sql");

  return sprintf ('SELECT %s%s%s%s',
    $offset
      ? do {
         push @{$self->{pre_select_bind}}, [ $self->__offset_bindtype => $offset];
         'SKIP ? '
      }
      : ''
    ,
    do {
       push @{$self->{pre_select_bind}}, [ $self->__rows_bindtype => $rows ];
       'FIRST ? '
    },
    $sql,
    $self->_parse_rs_attrs ($rs_attrs),
  );
}

sub _FirstSkip {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  $sql =~ s/^ \s* SELECT \s+ //ix
    or $self->throw_exception("Unrecognizable SELECT: $sql");

  return sprintf ('SELECT %s%s%s%s',
    do {
       push @{$self->{pre_select_bind}}, [ $self->__rows_bindtype => $rows ];
       'FIRST ? '
    },
    $offset
      ? do {
         push @{$self->{pre_select_bind}}, [ $self->__offset_bindtype => $offset];
         'SKIP ? '
      }
      : ''
    ,
    $sql,
    $self->_parse_rs_attrs ($rs_attrs),
  );
}

sub _RowNum {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  my $sq_attrs = $self->_subqueried_limit_attrs ($sql, $rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});
  my $idx_name = $self->_quote ('rownum__index');
  my $order_group_having = $self->_parse_rs_attrs($rs_attrs);


  # if no offset (e.g. first page) - we can skip one of the subqueries
  if (! $offset) {
    push @{$self->{limit_bind}}, [ $self->__rows_bindtype => $rows ];

    return <<EOS;
SELECT $sq_attrs->{selection_outer} FROM (
  SELECT $sq_attrs->{selection_inner} $sq_attrs->{query_leftover}${order_group_having}
) $qalias WHERE ROWNUM <= ?
EOS
  }

  #
  # There are two ways to limit in Oracle, one vastly faster than the other
  # on large resultsets: https://decipherinfosys.wordpress.com/2007/08/09/paging-and-countstopkey-optimization/
  # However Oracle is retarded and does not preserve stable ROWNUM() values
  # when called twice in the same scope. Therefore unless the resultset is
  # ordered by a unique set of columns, it is not safe to use the faster
  # method, and the slower BETWEEN query is used instead
  #
  # FIXME - this is quite expensive, and does not perform caching of any sort
  # as soon as some of the SQLMaker-inlining work becomes viable consider adding
  # some rudimentary caching support
  if (
    $rs_attrs->{order_by}
      and
    $rs_attrs->{result_source}->storage->_order_by_is_stable(
      @{$rs_attrs}{qw/from order_by where/}
    )
  ) {
    push @{$self->{limit_bind}}, [ $self->__total_bindtype => $offset + $rows ], [ $self->__offset_bindtype => $offset + 1 ];

    return <<EOS;
SELECT $sq_attrs->{selection_outer} FROM (
  SELECT $sq_attrs->{selection_outer}, ROWNUM AS $idx_name FROM (
    SELECT $sq_attrs->{selection_inner} $sq_attrs->{query_leftover}${order_group_having}
  ) $qalias WHERE ROWNUM <= ?
) $qalias WHERE $idx_name >= ?
EOS
  }
  else {
    push @{$self->{limit_bind}}, [ $self->__offset_bindtype => $offset + 1 ], [ $self->__total_bindtype => $offset + $rows ];

    return <<EOS;
SELECT $sq_attrs->{selection_outer} FROM (
  SELECT $sq_attrs->{selection_outer}, ROWNUM AS $idx_name FROM (
    SELECT $sq_attrs->{selection_inner} $sq_attrs->{query_leftover}${order_group_having}
  ) $qalias
) $qalias WHERE $idx_name BETWEEN ? AND ?
EOS
  }
}

# used by _Top and _FetchFirst below
sub _prep_for_skimming_limit {
  my ( $self, $sql, $rs_attrs ) = @_;

  # get selectors
  my $sq_attrs = $self->_subqueried_limit_attrs ($sql, $rs_attrs);

  my $requested_order = delete $rs_attrs->{order_by};
  $sq_attrs->{order_by_requested} = $self->_order_by ($requested_order);
  $sq_attrs->{grpby_having} = $self->_parse_rs_attrs ($rs_attrs);

  # without an offset things are easy
  if (! $rs_attrs->{offset}) {
    $sq_attrs->{order_by_inner} = $sq_attrs->{order_by_requested};
  }
  else {
    $sq_attrs->{quoted_rs_alias} = $self->_quote ($rs_attrs->{alias});

    # localise as we already have all the bind values we need
    local $self->{order_bind};

    # make up an order unless supplied or sanity check what we are given
    my $inner_order;
    if ($sq_attrs->{order_by_requested}) {
      $self->throw_exception (
        'Unable to safely perform "skimming type" limit with supplied unstable order criteria'
      ) unless ($rs_attrs->{result_source}->schema->storage->_order_by_is_stable(
        $rs_attrs->{from},
        $requested_order,
        $rs_attrs->{where},
      ));

      $inner_order = $requested_order;
    }
    else {
      $inner_order = [ map
        { "$rs_attrs->{alias}.$_" }
        ( @{
          $rs_attrs->{result_source}->_identifying_column_set
            ||
          $self->throw_exception(sprintf(
            'Unable to auto-construct stable order criteria for "skimming type" limit '
          . "dialect based on source '%s'", $rs_attrs->{result_source}->name) );
        } )
      ];
    }

    $sq_attrs->{order_by_inner} = $self->_order_by ($inner_order);

    my @out_chunks;
    for my $ch ($self->_order_by_chunks ($inner_order)) {
      $ch = $ch->[0] if ref $ch eq 'ARRAY';

      ($ch, my $is_desc) = $self->_split_order_chunk($ch);

      # !NOTE! outside chunks come in reverse order ( !$is_desc )
      push @out_chunks, { ($is_desc ? '-asc' : '-desc') => \$ch };
    }

    $sq_attrs->{order_by_middle} = $self->_order_by (\@out_chunks);

    # this is the order supplement magic
    $sq_attrs->{selection_middle} = $sq_attrs->{selection_outer};
    if (my $extra_order_sel = $sq_attrs->{order_supplement}) {
      for my $extra_col (sort
        { $extra_order_sel->{$a} cmp $extra_order_sel->{$b} }
        keys %$extra_order_sel
      ) {
        $sq_attrs->{selection_inner} .= sprintf (', %s AS %s',
          $extra_col,
          $extra_order_sel->{$extra_col},
        );

        $sq_attrs->{selection_middle} .= ', ' . $extra_order_sel->{$extra_col};
      }

      # Whatever order bindvals there are, they will be realiased and
      # reselected, and need to show up at end of the initial inner select
      push @{$self->{select_bind}}, @{$self->{order_bind}};
    }

    # and this is order re-alias magic
    for my $map ($sq_attrs->{order_supplement}, $sq_attrs->{outer_renames}) {
      for my $col (sort { (length $b) <=> (length $a) } keys %{$map||{}}) {
        my $re_col = quotemeta ($col);
        $_ =~ s/$re_col/$map->{$col}/
          for ($sq_attrs->{order_by_middle}, $sq_attrs->{order_by_requested});
      }
    }
  }

  $sq_attrs;
}

sub _Top {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  my $lim = $self->_prep_for_skimming_limit($sql, $rs_attrs);

  $sql = sprintf ('SELECT TOP %u %s %s %s %s',
    $rows + ($offset||0),
    $offset ? $lim->{selection_inner} : $lim->{selection_original},
    $lim->{query_leftover},
    $lim->{grpby_having},
    $lim->{order_by_inner},
  );

  $sql = sprintf ('SELECT TOP %u %s FROM ( %s ) %s %s',
    $rows,
    $lim->{selection_middle},
    $sql,
    $lim->{quoted_rs_alias},
    $lim->{order_by_middle},
  ) if $offset;

  $sql = sprintf ('SELECT %s FROM ( %s ) %s %s',
    $lim->{selection_outer},
    $sql,
    $lim->{quoted_rs_alias},
    $lim->{order_by_requested},
  ) if $offset and (
    $lim->{order_by_requested} or $lim->{selection_middle} ne $lim->{selection_outer}
  );

  return $sql;
}

sub _FetchFirst {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  my $lim = $self->_prep_for_skimming_limit($sql, $rs_attrs);

  $sql = sprintf ('SELECT %s %s %s %s FETCH FIRST %u ROWS ONLY',
    $offset ? $lim->{selection_inner} : $lim->{selection_original},
    $lim->{query_leftover},
    $lim->{grpby_having},
    $lim->{order_by_inner},
    $rows + ($offset||0),
  );

  $sql = sprintf ('SELECT %s FROM ( %s ) %s %s FETCH FIRST %u ROWS ONLY',
    $lim->{selection_middle},
    $sql,
    $lim->{quoted_rs_alias},
    $lim->{order_by_middle},
    $rows,
  ) if $offset;


  $sql = sprintf ('SELECT %s FROM ( %s ) %s %s',
    $lim->{selection_outer},
    $sql,
    $lim->{quoted_rs_alias},
    $lim->{order_by_requested},
  ) if $offset and (
    $lim->{order_by_requested} or $lim->{selection_middle} ne $lim->{selection_outer}
  );

  return $sql;
}

sub _GenericSubQ {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  my $main_rsrc = $rs_attrs->{result_source};

  # Explicitly require an order_by
  # GenSubQ is slow enough as it is, just emulating things
  # like in other cases is not wise - make the user work
  # to shoot their DBA in the foot
  $self->throw_exception (
    'Generic Subquery Limit does not work on resultsets without an order. Provide a stable, '
  . 'main-table-based order criteria.'
  ) unless $rs_attrs->{order_by};

  my $usable_order_colinfo = $main_rsrc->storage->_extract_colinfo_of_stable_main_source_order_by_portion(
    $rs_attrs
  );

  $self->throw_exception(
    'Generic Subquery Limit can not work with order criteria based on sources other than the main one'
  ) if (
    ! keys %{$usable_order_colinfo||{}}
      or
    grep
      { $_->{-source_alias} ne $rs_attrs->{alias} }
      (values %$usable_order_colinfo)
  );

###
###
### we need to know the directions after we figured out the above - reextract *again*
### this is eyebleed - trying to get it to work at first
  my $supplied_order = delete $rs_attrs->{order_by};

  my @order_bits = do {
    local $self->{quote_char};
    local $self->{order_bind};
    map { ref $_ ? $_->[0] : $_ } $self->_order_by_chunks ($supplied_order)
  };

  # truncate to what we'll use
  $#order_bits = ( (keys %$usable_order_colinfo) - 1 );

  # @order_bits likely will come back quoted (due to how the prefetch
  # rewriter operates
  # Hence supplement the column_info lookup table with quoted versions
  if ($self->quote_char) {
    $usable_order_colinfo->{$self->_quote($_)} = $usable_order_colinfo->{$_}
      for keys %$usable_order_colinfo;
  }

# calculate the condition
  my $count_tbl_alias = 'rownum__emulation';
  my $main_alias = $rs_attrs->{alias};
  my $main_tbl_name = $main_rsrc->name;

  my (@unqualified_names, @qualified_names, @is_desc, @new_order_by);

  for my $bit (@order_bits) {

    ($bit, my $is_desc) = $self->_split_order_chunk($bit);

    push @is_desc, $is_desc;
    push @unqualified_names, $usable_order_colinfo->{$bit}{-colname};
    push @qualified_names, $usable_order_colinfo->{$bit}{-fq_colname};

    push @new_order_by, { ($is_desc ? '-desc' : '-asc') => $usable_order_colinfo->{$bit}{-fq_colname} };
  };

  my (@where_cond, @skip_colpair_stack);
  for my $i (0 .. $#order_bits) {
    my $ci = $usable_order_colinfo->{$order_bits[$i]};

    my ($subq_col, $main_col) = map { "$_.$ci->{-colname}" } ($count_tbl_alias, $main_alias);
    my $cur_cond = { $subq_col => { ($is_desc[$i] ? '>' : '<') => { -ident => $main_col } } };

    push @skip_colpair_stack, [
      { $main_col => { -ident => $subq_col } },
    ];

    # we can trust the nullability flag because
    # we already used it during _id_col_set resolution
    #
    if ($ci->{is_nullable}) {
      push @{$skip_colpair_stack[-1]}, { $main_col => undef, $subq_col=> undef };

      $cur_cond = [
        {
          ($is_desc[$i] ? $subq_col : $main_col) => { '!=', undef },
          ($is_desc[$i] ? $main_col : $subq_col) => undef,
        },
        {
          $subq_col => { '!=', undef },
          $main_col => { '!=', undef },
          -and => $cur_cond,
        },
      ];
    }

    push @where_cond, { '-and', => [ @skip_colpair_stack[0..$i-1], $cur_cond ] };
  }

# reuse the sqlmaker WHERE, this will not be returning binds
  my $counted_where = do {
    local $self->{where_bind};
    $self->where(\@where_cond);
  };

# construct the rownum condition by hand
  my $rownum_cond;
  if ($offset) {
    $rownum_cond = 'BETWEEN ? AND ?';
    push @{$self->{limit_bind}},
      [ $self->__offset_bindtype => $offset ],
      [ $self->__total_bindtype => $offset + $rows - 1]
    ;
  }
  else {
    $rownum_cond = '< ?';
    push @{$self->{limit_bind}},
      [ $self->__rows_bindtype => $rows ]
    ;
  }

# and what we will order by inside
  my $inner_order_sql = do {
    local $self->{order_bind};

    my $s = $self->_order_by (\@new_order_by);

    $self->throw_exception('Inner gensubq order may not contain binds... something went wrong')
      if @{$self->{order_bind}};

    $s;
  };

### resume originally scheduled programming
###
###

  # we need to supply the order for the supplements to be properly calculated
  my $sq_attrs = $self->_subqueried_limit_attrs (
    $sql, { %$rs_attrs, order_by => \@new_order_by }
  );

  my $in_sel = $sq_attrs->{selection_inner};

  # add the order supplement (if any) as this is what will be used for the outer WHERE
  $in_sel .= ", $_" for sort keys %{$sq_attrs->{order_supplement}};

  my $group_having_sql = $self->_parse_rs_attrs($rs_attrs);


  return sprintf ("
SELECT $sq_attrs->{selection_outer}
  FROM (
    SELECT $in_sel $sq_attrs->{query_leftover}${group_having_sql}
  ) %s
WHERE ( SELECT COUNT(*) FROM %s %s $counted_where ) $rownum_cond
$inner_order_sql
  ", map { $self->_quote ($_) } (
    $rs_attrs->{alias},
    $main_tbl_name,
    $count_tbl_alias,
  ));
}


# !!! THIS IS ALSO HORRIFIC !!! /me ashamed
#
# Generates inner/outer select lists for various limit dialects
# which result in one or more subqueries (e.g. RNO, Top, RowNum)
# Any non-main-table columns need to have their table qualifier
# turned into a column alias (otherwise names in subqueries clash
# and/or lose their source table)
#
# Returns mangled proto-sql, inner/outer strings of SQL QUOTED selectors
# with aliases (to be used in whatever select statement), and an alias
# index hashref of QUOTED SEL => QUOTED ALIAS pairs (to maybe be used
# for string-subst higher up).
# If an order_by is supplied, the inner select needs to bring out columns
# used in implicit (non-selected) orders, and the order condition itself
# needs to be realiased to the proper names in the outer query. Thus we
# also return a hashref (order doesn't matter) of QUOTED EXTRA-SEL =>
# QUOTED ALIAS pairs, which is a list of extra selectors that do *not*
# exist in the original select list
sub _subqueried_limit_attrs {
  my ($self, $proto_sql, $rs_attrs) = @_;

  $self->throw_exception(
    'Limit dialect implementation usable only in the context of DBIC (missing $rs_attrs)'
  ) unless ref ($rs_attrs) eq 'HASH';

  # mangle the input sql as we will be replacing the selector entirely
  unless (
    $rs_attrs->{_selector_sql}
      and
    $proto_sql =~ s/^ \s* SELECT \s* \Q$rs_attrs->{_selector_sql}//ix
  ) {
    $self->throw_exception("Unrecognizable SELECT: $proto_sql");
  }

  my ($re_sep, $re_alias) = map { quotemeta $_ } ( $self->{name_sep}, $rs_attrs->{alias} );

  # correlate select and as, build selection index
  my (@sel, $in_sel_index);
  for my $i (0 .. $#{$rs_attrs->{select}}) {

    my $s = $rs_attrs->{select}[$i];
    my $sql_alias = (ref $s) eq 'HASH' ? $s->{-as} : undef;

    # we throw away the @bind here deliberately
    my ($sql_sel) = $self->_recurse_fields ($s);

    push @sel, {
      arg => $s,
      sql => $sql_sel,
      unquoted_sql => do {
        local $self->{quote_char};
        ($self->_recurse_fields ($s))[0]; # ignore binds again
      },
      as =>
        $sql_alias
          ||
        $rs_attrs->{as}[$i]
          ||
        $self->throw_exception("Select argument $i ($s) without corresponding 'as'")
      ,
    };

    # anything with a placeholder in it needs re-selection
    $in_sel_index->{$sql_sel}++ unless $sql_sel =~ / (?: ^ | \W ) \? (?: \W | $ ) /x;

    $in_sel_index->{$self->_quote ($sql_alias)}++ if $sql_alias;

    # record unqualified versions too, so we do not have
    # to reselect the same column twice (in qualified and
    # unqualified form)
    if (! ref $s && $sql_sel =~ / $re_sep (.+) $/x) {
      $in_sel_index->{$1}++;
    }
  }


  # re-alias and remove any name separators from aliases,
  # unless we are dealing with the current source alias
  # (which will transcend the subqueries as it is necessary
  # for possible further chaining)
  # same for anything we do not recognize
  my ($sel, $renamed);
  for my $node (@sel) {
    push @{$sel->{original}}, $node->{sql};

    if (
      ! $in_sel_index->{$node->{sql}}
        or
      $node->{as} =~ / (?<! ^ $re_alias ) \. /x
        or
      $node->{unquoted_sql} =~ / (?<! ^ $re_alias ) $re_sep /x
    ) {
      $node->{as} = $self->_unqualify_colname($node->{as});
      my $quoted_as = $self->_quote($node->{as});
      push @{$sel->{inner}}, sprintf '%s AS %s', $node->{sql}, $quoted_as;
      push @{$sel->{outer}}, $quoted_as;
      $renamed->{$node->{sql}} = $quoted_as;
    }
    else {
      push @{$sel->{inner}}, $node->{sql};
      push @{$sel->{outer}}, $self->_quote (ref $node->{arg} ? $node->{as} : $node->{arg});
    }
  }

  # see if the order gives us anything
  my $extra_order_sel;
  for my $chunk ($self->_order_by_chunks ($rs_attrs->{order_by})) {
    # order with bind
    $chunk = $chunk->[0] if (ref $chunk) eq 'ARRAY';
    ($chunk) = $self->_split_order_chunk($chunk);

    next if $in_sel_index->{$chunk};

    $extra_order_sel->{$chunk} ||= $self->_quote (
      'ORDER__BY__' . sprintf '%03d', scalar keys %{$extra_order_sel||{}}
    );
  }

  return {
    query_leftover => $proto_sql,
    (map {( "selection_$_" => join (', ', @{$sel->{$_}} ) )} keys %$sel ),
    outer_renames => $renamed,
    order_supplement => $extra_order_sel,
  };
}

sub _unqualify_colname {
  my ($self, $fqcn) = @_;
  $fqcn =~ s/ \. /__/xg;
  return $fqcn;
}

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;

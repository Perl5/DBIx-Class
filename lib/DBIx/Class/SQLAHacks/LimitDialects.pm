package DBIx::Class::SQLAHacks::LimitDialects;

use warnings;
use strict;

use Carp::Clan qw/^DBIx::Class|^SQL::Abstract|^Try::Tiny/;
use List::Util 'first';
use namespace::clean;

# FIXME
# This dialect has not been ported to the subquery-realiasing code
# that all other subquerying dialects are using. It is very possible
# that this dialect is entirely unnecessary - it is currently only
# used by ::Storage::DBI::ODBC::DB2_400_SQL which *should* be able to
# just subclass ::Storage::DBI::DB2 and use the already rewritten
# RowNumberOver. However nobody has access to this specific database
# engine, thus keeping legacy code as-is
# IF someone ever manages to test DB2-AS/400 with RNO, all the code
# in this block should go on to meet its maker
{
  sub _FetchFirst {
    my ( $self, $sql, $order, $rows, $offset ) = @_;

    my $last = $rows + $offset;

    my ( $order_by_up, $order_by_down ) = $self->_order_directions( $order );

    $sql = "
      SELECT * FROM (
        SELECT * FROM (
          $sql
          $order_by_up
          FETCH FIRST $last ROWS ONLY
        ) foo
        $order_by_down
        FETCH FIRST $rows ROWS ONLY
      ) bar
      $order_by_up
    ";

    return $sql;
  }

  sub _order_directions {
    my ( $self, $order ) = @_;

    return unless $order;

    my $ref = ref $order;

    my @order;

    CASE: {
      @order = @$order,     last CASE if $ref eq 'ARRAY';
      @order = ( $order ),  last CASE unless $ref;
      @order = ( $$order ), last CASE if $ref eq 'SCALAR';
      croak __PACKAGE__ . ": Unsupported data struct $ref for ORDER BY";
    }

    my ( $order_by_up, $order_by_down );

    foreach my $spec ( @order )
    {
        my @spec = split ' ', $spec;
        croak( "bad column order spec: $spec" ) if @spec > 2;
        push( @spec, 'ASC' ) unless @spec == 2;
        my ( $col, $up ) = @spec; # or maybe down
        $up = uc( $up );
        croak( "bad direction: $up" ) unless $up =~ /^(?:ASC|DESC)$/;
        $order_by_up .= ", $col $up";
        my $down = $up eq 'ASC' ? 'DESC' : 'ASC';
        $order_by_down .= ", $col $down";
    }

    s/^,/ORDER BY/ for ( $order_by_up, $order_by_down );

    return $order_by_up, $order_by_down;
  }
}
### end-of-FIXME

# PostgreSQL and SQLite
sub _LimitOffset {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    $sql .= $self->_order_by( $order ) . " LIMIT $rows";
    $sql .= " OFFSET $offset" if +$offset;
    return $sql;
}

# MySQL and any SQL::Statement based DBD
sub _LimitXY {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    $sql .= $self->_order_by( $order ) . " LIMIT ";
    $sql .= "$offset, " if +$offset;
    $sql .= $rows;
    return $sql;
}
# ANSI standard Limit/Offset implementation. DB2 and MSSQL >= 2005 use this
sub _RowNumberOver {
  my ($self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # mangle the input sql as we will be replacing the selector
  $sql =~ s/^ \s* SELECT \s+ .+? \s+ (?= \b FROM \b )//ix
    or croak "Unrecognizable SELECT: $sql";

  # get selectors, and scan the order_by (if any)
  my ($in_sel, $out_sel, $alias_map, $extra_order_sel)
    = $self->_subqueried_limit_attrs ( $rs_attrs );

  # make up an order if none exists
  my $requested_order = (delete $rs_attrs->{order_by}) || $self->_rno_default_order;
  my $rno_ord = $self->_order_by ($requested_order);

  # this is the order supplement magic
  my $mid_sel = $out_sel;
  if ($extra_order_sel) {
    for my $extra_col (sort
      { $extra_order_sel->{$a} cmp $extra_order_sel->{$b} }
      keys %$extra_order_sel
    ) {
      $in_sel .= sprintf (', %s AS %s',
        $extra_col,
        $extra_order_sel->{$extra_col},
      );

      $mid_sel .= ', ' . $extra_order_sel->{$extra_col};
    }
  }

  # and this is order re-alias magic
  for ($extra_order_sel, $alias_map) {
    for my $col (keys %$_) {
      my $re_col = quotemeta ($col);
      $rno_ord =~ s/$re_col/$_->{$col}/;
    }
  }

  # whatever is left of the order_by (only where is processed at this point)
  my $group_having = $self->_parse_rs_attrs($rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});
  my $idx_name = $self->_quote ('rno__row__index');

  $sql = sprintf (<<EOS, $offset + 1, $offset + $rows, );

SELECT $out_sel FROM (
  SELECT $mid_sel, ROW_NUMBER() OVER( $rno_ord ) AS $idx_name FROM (
    SELECT $in_sel ${sql}${group_having}
  ) $qalias
) $qalias WHERE $idx_name BETWEEN %u AND %u

EOS

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}

# some databases are happy with OVER (), some need OVER (ORDER BY (SELECT (1)) )
sub _rno_default_order {
  return undef;
}

# Informix specific limit, almost like LIMIT/OFFSET
# According to SQLA::Limit informix also supports
# SKIP X LIMIT Y (in addition to SKIP X FIRST Y)
sub _SkipFirst {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  $sql =~ s/^ \s* SELECT \s+ //ix
    or croak "Unrecognizable SELECT: $sql";

  return sprintf ('SELECT %s%s%s%s',
    $offset
      ? sprintf ('SKIP %u ', $offset)
      : ''
    ,
    sprintf ('FIRST %u ', $rows),
    $sql,
    $self->_parse_rs_attrs ($rs_attrs),
  );
}

# Firebird specific limit, reverse of _SkipFirst for Informix
# According to SQLA::Limit firebird/interbase also supports
# ROWS X TO Y (in addition to FIRST X SKIP Y)
sub _FirstSkip {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  $sql =~ s/^ \s* SELECT \s+ //ix
    or croak "Unrecognizable SELECT: $sql";

  return sprintf ('SELECT %s%s%s%s',
    sprintf ('FIRST %u ', $rows),
    $offset
      ? sprintf ('SKIP %u ', $offset)
      : ''
    ,
    $sql,
    $self->_parse_rs_attrs ($rs_attrs),
  );
}

# WhOracle limits
sub _RowNum {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # mangle the input sql as we will be replacing the selector
  $sql =~ s/^ \s* SELECT \s+ .+? \s+ (?= \b FROM \b )//ix
    or croak "Unrecognizable SELECT: $sql";

  my ($insel, $outsel) = $self->_subqueried_limit_attrs ($rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});
  my $idx_name = $self->_quote ('rownum__index');
  my $order_group_having = $self->_parse_rs_attrs($rs_attrs);

  $sql = sprintf (<<EOS, $offset + 1, $offset + $rows, );

SELECT $outsel FROM (
  SELECT $outsel, ROWNUM $idx_name FROM (
    SELECT $insel ${sql}${order_group_having}
  ) $qalias
) $qalias WHERE $idx_name BETWEEN %u AND %u

EOS

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}

# Crappy Top based Limit/Offset support. Legacy for MSSQL < 2005
sub _Top {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # mangle the input sql as we will be replacing the selector
  $sql =~ s/^ \s* SELECT \s+ .+? \s+ (?= \b FROM \b )//ix
    or croak "Unrecognizable SELECT: $sql";

  # get selectors
  my ($in_sel, $out_sel, $alias_map, $extra_order_sel)
    = $self->_subqueried_limit_attrs ($rs_attrs);

  my $requested_order = delete $rs_attrs->{order_by};

  my $order_by_requested = $self->_order_by ($requested_order);

  # make up an order unless supplied
  my $inner_order = ($order_by_requested
    ? $requested_order
    : [ map
      { join ('', $rs_attrs->{alias}, $self->{name_sep}||'.', $_ ) }
      ( $rs_attrs->{_rsroot_source_handle}->resolve->_pri_cols )
    ]
  );

  my ($order_by_inner, $order_by_reversed);

  # localise as we already have all the bind values we need
  {
    local $self->{order_bind};
    $order_by_inner = $self->_order_by ($inner_order);

    my @out_chunks;
    for my $ch ($self->_order_by_chunks ($inner_order)) {
      $ch = $ch->[0] if ref $ch eq 'ARRAY';

      $ch =~ s/\s+ ( ASC|DESC ) \s* $//ix;
      my $dir = uc ($1||'ASC');

      push @out_chunks, \join (' ', $ch, $dir eq 'ASC' ? 'DESC' : 'ASC' );
    }

    $order_by_reversed = $self->_order_by (\@out_chunks);
  }

  # this is the order supplement magic
  my $mid_sel = $out_sel;
  if ($extra_order_sel) {
    for my $extra_col (sort
      { $extra_order_sel->{$a} cmp $extra_order_sel->{$b} }
      keys %$extra_order_sel
    ) {
      $in_sel .= sprintf (', %s AS %s',
        $extra_col,
        $extra_order_sel->{$extra_col},
      );

      $mid_sel .= ', ' . $extra_order_sel->{$extra_col};
    }

    # since whatever order bindvals there are, they will be realiased
    # and need to show up in front of the entire initial inner subquery
    # Unshift *from_bind* to make this happen (horrible, horrible, but
    # we don't have another mechanism yet)
    unshift @{$self->{from_bind}}, @{$self->{order_bind}};
  }

  # and this is order re-alias magic
  for my $map ($extra_order_sel, $alias_map) {
    for my $col (keys %$map) {
      my $re_col = quotemeta ($col);
      $_ =~ s/$re_col/$map->{$col}/
        for ($order_by_reversed, $order_by_requested);
    }
  }

  # generate the rest of the sql
  my $grpby_having = $self->_parse_rs_attrs ($rs_attrs);

  my $quoted_rs_alias = $self->_quote ($rs_attrs->{alias});

  $sql = sprintf ('SELECT TOP %u %s %s %s %s',
    $rows + ($offset||0),
    $in_sel,
    $sql,
    $grpby_having,
    $order_by_inner,
  );

  $sql = sprintf ('SELECT TOP %u %s FROM ( %s ) %s %s',
    $rows,
    $mid_sel,
    $sql,
    $quoted_rs_alias,
    $order_by_reversed,
  ) if $offset;

  $sql = sprintf ('SELECT TOP %u %s FROM ( %s ) %s %s',
    $rows,
    $out_sel,
    $sql,
    $quoted_rs_alias,
    $order_by_requested,
  ) if ( ($offset && $order_by_requested) || ($mid_sel ne $out_sel) );

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}

# This for Sybase ASE, to use SET ROWCOUNT when there is no offset, and
# GenericSubQ otherwise.
sub _RowCountOrGenericSubQ {
  my $self = shift;
  my ($sql, $rs_attrs, $rows, $offset) = @_;

  return $self->_GenericSubQ(@_) if $offset;

  return sprintf <<"EOF", $rows, $sql;
SET ROWCOUNT %d
%s
SET ROWCOUNT 0
EOF
}

# This is the most evil limit "dialect" (more of a hack) for *really*
# stupid databases. It works by ordering the set by some unique column,
# and calculating amount of rows that have a less-er value (thus
# emulating a RowNum-like index). Of course this implies the set can
# only be ordered by a single unique columns.
sub _GenericSubQ {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  my $root_rsrc = $rs_attrs->{_rsroot_source_handle}->resolve;
  my $root_tbl_name = $root_rsrc->name;

  # mangle the input sql as we will be replacing the selector
  $sql =~ s/^ \s* SELECT \s+ .+? \s+ (?= \b FROM \b )//ix
    or croak "Unrecognizable SELECT: $sql";

  my ($order_by, @rest) = do {
    local $self->{quote_char};
    $self->_order_by_chunks ($rs_attrs->{order_by})
  };

  unless (
    $order_by
      &&
    ! @rest
      &&
    ( ! ref $order_by
        ||
      ( ref $order_by eq 'ARRAY' and @$order_by == 1 )
    )
  ) {
    croak (
      'Generic Subquery Limit does not work on resultsets without an order, or resultsets '
    . 'with complex order criteria (multicolumn and/or functions). Provide a single, '
    . 'unique-column order criteria.'
    );
  }

  ($order_by) = @$order_by if ref $order_by;

  $order_by =~ s/\s+ ( ASC|DESC ) \s* $//ix;
  my $direction = lc ($1 || 'asc');

  my ($unq_sort_col) = $order_by =~ /(?:^|\.)([^\.]+)$/;

  my $inf = $root_rsrc->storage->_resolve_column_info (
    $rs_attrs->{from}, [$order_by, $unq_sort_col]
  );

  my $ord_colinfo = $inf->{$order_by} || croak "Unable to determine source of order-criteria '$order_by'";

  if ($ord_colinfo->{-result_source}->name ne $root_tbl_name) {
    croak "Generic Subquery Limit order criteria can be only based on the root-source '"
        . $root_rsrc->source_name . "' (aliased as '$rs_attrs->{alias}')";
  }

  # make sure order column is qualified
  $order_by = "$rs_attrs->{alias}.$order_by"
    unless $order_by =~ /^$rs_attrs->{alias}\./;

  my $is_u;
  my $ucs = { $root_rsrc->unique_constraints };
  for (values %$ucs ) {
    if (@$_ == 1 && "$rs_attrs->{alias}.$_->[0]" eq $order_by) {
      $is_u++;
      last;
    }
  }
  croak "Generic Subquery Limit order criteria column '$order_by' must be unique (no unique constraint found)"
    unless $is_u;

  my ($in_sel, $out_sel, $alias_map, $extra_order_sel)
    = $self->_subqueried_limit_attrs ($rs_attrs);

  my $cmp_op = $direction eq 'desc' ? '>' : '<';
  my $count_tbl_alias = 'rownum__emulation';

  my $order_sql = $self->_order_by (delete $rs_attrs->{order_by});
  my $group_having_sql = $self->_parse_rs_attrs($rs_attrs);

  # add the order supplement (if any) as this is what will be used for the outer WHERE
  $in_sel .= ", $_" for keys %{$extra_order_sel||{}};

  $sql = sprintf (<<EOS,
SELECT $out_sel
  FROM (
    SELECT $in_sel ${sql}${group_having_sql}
  ) %s
WHERE ( SELECT COUNT(*) FROM %s %s WHERE %s $cmp_op %s ) %s
$order_sql
EOS
    ( map { $self->_quote ($_) } (
      $rs_attrs->{alias},
      $root_tbl_name,
      $count_tbl_alias,
      "$count_tbl_alias.$unq_sort_col",
      $order_by,
    )),
    $offset
      ? sprintf ('BETWEEN %u AND %u', $offset, $offset + $rows - 1)
      : sprintf ('< %u', $rows )
    ,
  );

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}


# !!! THIS IS ALSO HORRIFIC !!! /me ashamed
#
# Generates inner/outer select lists for various limit dialects
# which result in one or more subqueries (e.g. RNO, Top, RowNum)
# Any non-root-table columns need to have their table qualifier
# turned into a column alias (otherwise names in subqueries clash
# and/or lose their source table)
#
# Returns inner/outer strings of SQL QUOTED selectors with aliases
# (to be used in whatever select statement), and an alias index hashref
# of QUOTED SEL => QUOTED ALIAS pairs (to maybe be used for string-subst
# higher up).
# If an order_by is supplied, the inner select needs to bring out columns
# used in implicit (non-selected) orders, and the order condition itself
# needs to be realiased to the proper names in the outer query. Thus we
# also return a hashref (order doesn't matter) of QUOTED EXTRA-SEL =>
# QUOTED ALIAS pairs, which is a list of extra selectors that do *not*
# exist in the original select list

sub _subqueried_limit_attrs {
  my ($self, $rs_attrs) = @_;

  croak 'Limit dialect implementation usable only in the context of DBIC (missing $rs_attrs)'
    unless ref ($rs_attrs) eq 'HASH';

  my ($re_sep, $re_alias) = map { quotemeta $_ } (
    $self->name_sep || '.',
    $rs_attrs->{alias},
  );

  # correlate select and as, build selection index
  my (@sel, $in_sel_index);
  for my $i (0 .. $#{$rs_attrs->{select}}) {

    my $s = $rs_attrs->{select}[$i];
    my $sql_sel = $self->_recurse_fields ($s);
    my $sql_alias = (ref $s) eq 'HASH' ? $s->{-as} : undef;


    push @sel, {
      sql => $sql_sel,
      unquoted_sql => do { local $self->{quote_char}; $self->_recurse_fields ($s) },
      as =>
        $sql_alias
          ||
        $rs_attrs->{as}[$i]
          ||
        croak "Select argument $i ($s) without corresponding 'as'"
      ,
    };

    $in_sel_index->{$sql_sel}++;
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
  my (@in_sel, @out_sel, %renamed);
  for my $node (@sel) {
    if (first { $_ =~ / (?<! ^ $re_alias ) $re_sep /x } ($node->{as}, $node->{unquoted_sql}) )  {
      $node->{as} = $self->_unqualify_colname($node->{as});
      my $quoted_as = $self->_quote($node->{as});
      push @in_sel, sprintf '%s AS %s', $node->{sql}, $quoted_as;
      push @out_sel, $quoted_as;
      $renamed{$node->{sql}} = $quoted_as;
    }
    else {
      push @in_sel, $node->{sql};
      push @out_sel, $self->_quote ($node->{as});
    }
  }

  # see if the order gives us anything
  my %extra_order_sel;
  for my $chunk ($self->_order_by_chunks ($rs_attrs->{order_by})) {
    # order with bind
    $chunk = $chunk->[0] if (ref $chunk) eq 'ARRAY';
    $chunk =~ s/\s+ (?: ASC|DESC ) \s* $//ix;

    next if $in_sel_index->{$chunk};

    $extra_order_sel{$chunk} ||= $self->_quote (
      'ORDER__BY__' . scalar keys %extra_order_sel
    );
  }

  return (
    (map { join (', ', @$_ ) } (
      \@in_sel,
      \@out_sel)
    ),
    \%renamed,
    keys %extra_order_sel ? \%extra_order_sel : (),
  );
}

sub _unqualify_colname {
  my ($self, $fqcn) = @_;
  my $re_sep = quotemeta($self->name_sep || '.');
  $fqcn =~ s/ $re_sep /__/xg;
  return $fqcn;
}

1;

package DBIx::Class::SQLMaker::LimitDialects;

use warnings;
use strict;

use List::Util 'first';
use namespace::clean;

# constants are used not only here, but also in comparison tests
sub __rows_bindtype () {
  +{ sqlt_datatype => 'integer' }
}
sub __offset_bindtype () {
  +{ sqlt_datatype => 'integer' }
}
sub __total_bindtype () {
  +{ sqlt_datatype => 'integer' }
}

=head1 NAME

DBIx::Class::SQLMaker::LimitDialects - SQL::Abstract::Limit-like functionality for DBIx::Class::SQLMaker

=head1 DESCRIPTION

This module replicates a lot of the functionality originally found in
L<SQL::Abstract::Limit>. While simple limits would work as-is, the more
complex dialects that require e.g. subqueries could not be reliably
implemented without taking full advantage of the metadata locked within
L<DBIx::Class::ResultSource> classes. After reimplementation of close to
80% of the L<SQL::Abstract::Limit> functionality it was deemed more
practical to simply make an independent DBIx::Class-specific limit-dialect
provider.

=head1 SQL LIMIT DIALECTS

Note that the actual implementations listed below never use C<*> literally.
Instead proper re-aliasing of selectors and order criteria is done, so that
the limit dialect are safe to use on joined resultsets with clashing column
names.

Currently the provided dialects are:

=head2 LimitOffset

 SELECT ... LIMIT $limit OFFSET $offset

Supported by B<PostgreSQL> and B<SQLite>

=cut
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

=head2 LimitXY

 SELECT ... LIMIT $offset $limit

Supported by B<MySQL> and any L<SQL::Statement> based DBD

=cut
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

=head2 RowNumberOver

 SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER( ORDER BY ... ) AS RNO__ROW__INDEX FROM (
   SELECT ...
  )
 ) WHERE RNO__ROW__INDEX BETWEEN ($offset+1) AND ($limit+$offset)


ANSI standard Limit/Offset implementation. Supported by B<DB2> and
B<< MSSQL >= 2005 >>.

=cut
sub _RowNumberOver {
  my ($self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # get selectors, and scan the order_by (if any)
  my ($stripped_sql, $in_sel, $out_sel, $alias_map, $extra_order_sel)
    = $self->_subqueried_limit_attrs ( $sql, $rs_attrs );

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

  push @{$self->{limit_bind}}, [ $self->__offset_bindtype => $offset + 1], [ $self->__total_bindtype => $offset + $rows ];

  return <<EOS;

SELECT $out_sel FROM (
  SELECT $mid_sel, ROW_NUMBER() OVER( $rno_ord ) AS $idx_name FROM (
    SELECT $in_sel ${stripped_sql}${group_having}
  ) $qalias
) $qalias WHERE $idx_name >= ? AND $idx_name <= ?

EOS

}

# some databases are happy with OVER (), some need OVER (ORDER BY (SELECT (1)) )
sub _rno_default_order {
  return undef;
}

=head2 SkipFirst

 SELECT SKIP $offset FIRST $limit * FROM ...

Suported by B<Informix>, almost like LimitOffset. According to
L<SQL::Abstract::Limit> C<... SKIP $offset LIMIT $limit ...> is also supported.

=cut
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

=head2 FirstSkip

 SELECT FIRST $limit SKIP $offset * FROM ...

Supported by B<Firebird/Interbase>, reverse of SkipFirst. According to
L<SQL::Abstract::Limit> C<... ROWS $limit TO $offset ...> is also supported.

=cut
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


=head2 RowNum

Depending on the resultset attributes one of:

 SELECT * FROM (
  SELECT *, ROWNUM rownum__index FROM (
   SELECT ...
  ) WHERE ROWNUM <= ($limit+$offset)
 ) WHERE rownum__index >= ($offset+1)

or

 SELECT * FROM (
  SELECT *, ROWNUM rownum__index FROM (
    SELECT ...
  )
 ) WHERE rownum__index BETWEEN ($offset+1) AND ($limit+$offset)

or

 SELECT * FROM (
    SELECT ...
  ) WHERE ROWNUM <= ($limit+1)

Supported by B<Oracle>.

=cut
sub _RowNum {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  my ($stripped_sql, $insel, $outsel) = $self->_subqueried_limit_attrs ($sql, $rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});
  my $idx_name = $self->_quote ('rownum__index');
  my $order_group_having = $self->_parse_rs_attrs($rs_attrs);

  #
  # There are two ways to limit in Oracle, one vastly faster than the other
  # on large resultsets: https://decipherinfosys.wordpress.com/2007/08/09/paging-and-countstopkey-optimization/
  # However Oracle is retarded and does not preserve stable ROWNUM() values
  # when called twice in the same scope. Therefore unless the resultset is
  # ordered by a unique set of columns, it is not safe to use the faster
  # method, and the slower BETWEEN query is used instead
  #
  # FIXME - this is quite expensive, and does not perform caching of any sort
  # as soon as some of the DQ work becomes viable consider switching this
  # over
  if (
    $rs_attrs->{order_by}
      and
    $rs_attrs->{_rsroot_rsrc}->storage->_order_by_is_stable(
      $rs_attrs->{from}, $rs_attrs->{order_by}
    )
  ) {
    # if offset is 0 (first page) the we can skip a subquery
    if (! $offset) {
      push @{$self->{limit_bind}}, [ $self->__rows_bindtype => $rows ];

      return <<EOS;
SELECT $outsel FROM (
  SELECT $insel ${stripped_sql}${order_group_having}
) $qalias WHERE ROWNUM <= ?
EOS
    }
    else {
      push @{$self->{limit_bind}}, [ $self->__total_bindtype => $offset + $rows ], [ $self->__offset_bindtype => $offset + 1 ];

      return <<EOS;
SELECT $outsel FROM (
  SELECT $outsel, ROWNUM $idx_name FROM (
    SELECT $insel ${stripped_sql}${order_group_having}
  ) $qalias WHERE ROWNUM <= ?
) $qalias WHERE $idx_name >= ?
EOS
    }
  }
  else {
    push @{$self->{limit_bind}}, [ $self->__offset_bindtype => $offset + 1 ], [ $self->__total_bindtype => $offset + $rows ];

    return <<EOS;
SELECT $outsel FROM (
  SELECT $outsel, ROWNUM $idx_name FROM (
    SELECT $insel ${stripped_sql}${order_group_having}
  ) $qalias
) $qalias WHERE $idx_name BETWEEN ? AND ?
EOS
  }
}

# used by _Top and _FetchFirst below
sub _prep_for_skimming_limit {
  my ( $self, $sql, $rs_attrs ) = @_;

  # get selectors
  my (%r, $alias_map, $extra_order_sel);
  ($r{inner_sql}, $r{in_sel}, $r{out_sel}, $alias_map, $extra_order_sel)
    = $self->_subqueried_limit_attrs ($sql, $rs_attrs);

  my $requested_order = delete $rs_attrs->{order_by};
  $r{order_by_requested} = $self->_order_by ($requested_order);

  # make up an order unless supplied or sanity check what we are given
  my $inner_order;
  if ($r{order_by_requested}) {
    $self->throw_exception (
      'Unable to safely perform "skimming type" limit with supplied unstable order criteria'
    ) unless $rs_attrs->{_rsroot_rsrc}->schema->storage->_order_by_is_stable(
      $rs_attrs->{from},
      $requested_order
    );

    $inner_order = $requested_order;
  }
  else {
    $inner_order = [ map
      { "$rs_attrs->{alias}.$_" }
      ( @{
        $rs_attrs->{_rsroot_rsrc}->_identifying_column_set
          ||
        $self->throw_exception(sprintf(
          'Unable to auto-construct stable order criteria for "skimming type" limit '
        . "dialect based on source '%s'", $rs_attrs->{_rsroot_rsrc}->name) );
      } )
    ];
  }

  # localise as we already have all the bind values we need
  {
    local $self->{order_bind};
    $r{order_by_inner} = $self->_order_by ($inner_order);

    my @out_chunks;
    for my $ch ($self->_order_by_chunks ($inner_order)) {
      $ch = $ch->[0] if ref $ch eq 'ARRAY';

      $ch =~ s/\s+ ( ASC|DESC ) \s* $//ix;
      my $dir = uc ($1||'ASC');

      push @out_chunks, \join (' ', $ch, $dir eq 'ASC' ? 'DESC' : 'ASC' );
    }

    $r{order_by_reversed} = $self->_order_by (\@out_chunks);
  }

  # this is the order supplement magic
  $r{mid_sel} = $r{out_sel};
  if ($extra_order_sel) {
    for my $extra_col (sort
      { $extra_order_sel->{$a} cmp $extra_order_sel->{$b} }
      keys %$extra_order_sel
    ) {
      $r{in_sel} .= sprintf (', %s AS %s',
        $extra_col,
        $extra_order_sel->{$extra_col},
      );

      $r{mid_sel} .= ', ' . $extra_order_sel->{$extra_col};
    }

    # Whatever order bindvals there are, they will be realiased and
    # need to show up in front of the entire initial inner subquery
    push @{$self->{pre_select_bind}}, @{$self->{order_bind}};
  }

  # if this is a part of something bigger, we need to add back all
  # the extra order_by's, as they may be relied upon by the outside
  # of a prefetch or something
  if ($rs_attrs->{_is_internal_subuery} and keys %$extra_order_sel) {
    $r{out_sel} .= sprintf ", $extra_order_sel->{$_} AS $_"
      for sort
        { $extra_order_sel->{$a} cmp $extra_order_sel->{$b} }
          grep { $_ !~ /[^\w\-]/ }  # ignore functions
          keys %$extra_order_sel
    ;
  }

  # and this is order re-alias magic
  for my $map ($extra_order_sel, $alias_map) {
    for my $col (keys %$map) {
      my $re_col = quotemeta ($col);
      $_ =~ s/$re_col/$map->{$col}/
        for ($r{order_by_reversed}, $r{order_by_requested});
    }
  }

  # generate the rest of the sql
  $r{grpby_having} = $self->_parse_rs_attrs ($rs_attrs);

  $r{quoted_rs_alias} = $self->_quote ($rs_attrs->{alias});

  \%r;
}

=head2 Top

 SELECT * FROM

 SELECT TOP $limit FROM (
  SELECT TOP $limit FROM (
   SELECT TOP ($limit+$offset) ...
  ) ORDER BY $reversed_original_order
 ) ORDER BY $original_order

Unreliable Top-based implementation, supported by B<< MSSQL < 2005 >>.

=head3 CAVEAT

Due to its implementation, this limit dialect returns B<incorrect results>
when $limit+$offset > total amount of rows in the resultset.

=cut

sub _Top {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  my %l = %{ $self->_prep_for_skimming_limit($sql, $rs_attrs) };

  $sql = sprintf ('SELECT TOP %u %s %s %s %s',
    $rows + ($offset||0),
    $l{in_sel},
    $l{inner_sql},
    $l{grpby_having},
    $l{order_by_inner},
  );

  $sql = sprintf ('SELECT TOP %u %s FROM ( %s ) %s %s',
    $rows,
    $l{mid_sel},
    $sql,
    $l{quoted_rs_alias},
    $l{order_by_reversed},
  ) if $offset;

  $sql = sprintf ('SELECT TOP %u %s FROM ( %s ) %s %s',
    $rows,
    $l{out_sel},
    $sql,
    $l{quoted_rs_alias},
    $l{order_by_requested},
  ) if ( ($offset && $l{order_by_requested}) || ($l{mid_sel} ne $l{out_sel}) );

  return $sql;
}

=head2 FetchFirst

 SELECT * FROM
 (
 SELECT * FROM (
  SELECT * FROM (
   SELECT * FROM ...
  ) ORDER BY $reversed_original_order
    FETCH FIRST $limit ROWS ONLY
 ) ORDER BY $original_order
   FETCH FIRST $limit ROWS ONLY
 )

Unreliable FetchFirst-based implementation, supported by B<< IBM DB2 <= V5R3 >>.

=head3 CAVEAT

Due to its implementation, this limit dialect returns B<incorrect results>
when $limit+$offset > total amount of rows in the resultset.

=cut

sub _FetchFirst {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  my %l = %{ $self->_prep_for_skimming_limit($sql, $rs_attrs) };

  $sql = sprintf ('SELECT %s %s %s %s FETCH FIRST %u ROWS ONLY',
    $l{in_sel},
    $l{inner_sql},
    $l{grpby_having},
    $l{order_by_inner},
    $rows + ($offset||0),
  );

  $sql = sprintf ('SELECT %s FROM ( %s ) %s %s FETCH FIRST %u ROWS ONLY',
    $l{mid_sel},
    $sql,
    $l{quoted_rs_alias},
    $l{order_by_reversed},
    $rows,
  ) if $offset;

  $sql = sprintf ('SELECT %s FROM ( %s ) %s %s FETCH FIRST %u ROWS ONLY',
    $l{out_sel},
    $sql,
    $l{quoted_rs_alias},
    $l{order_by_requested},
    $rows,
  ) if ( ($offset && $l{order_by_requested}) || ($l{mid_sel} ne $l{out_sel}) );

  return $sql;
}

=head2 RowCountOrGenericSubQ

This is not exactly a limit dialect, but more of a proxy for B<Sybase ASE>.
If no $offset is supplied the limit is simply performed as:

 SET ROWCOUNT $limit
 SELECT ...
 SET ROWCOUNT 0

Otherwise we fall back to L</GenericSubQ>

=cut

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

=head2 GenericSubQ

 SELECT * FROM (
  SELECT ...
 )
 WHERE (
  SELECT COUNT(*) FROM $original_table cnt WHERE cnt.id < $original_table.id
 ) BETWEEN $offset AND ($offset+$rows-1)

This is the most evil limit "dialect" (more of a hack) for I<really> stupid
databases. It works by ordering the set by some unique column, and calculating
the amount of rows that have a less-er value (thus emulating a L</RowNum>-like
index). Of course this implies the set can only be ordered by a single unique
column. Also note that this technique can be and often is B<excruciatingly
slow>.

Currently used by B<Sybase ASE>, due to lack of any other option.

=cut
sub _GenericSubQ {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  my $root_rsrc = $rs_attrs->{_rsroot_rsrc};
  my $root_tbl_name = $root_rsrc->name;

  my ($first_order_by) = do {
    local $self->{quote_char};
    map { ref $_ ? $_->[0] : $_ } $self->_order_by_chunks ($rs_attrs->{order_by})
  } or $self->throw_exception (
    'Generic Subquery Limit does not work on resultsets without an order. Provide a single, '
  . 'unique-column order criteria.'
  );

  $first_order_by =~ s/\s+ ( ASC|DESC ) \s* $//ix;
  my $direction = lc ($1 || 'asc');

  my ($first_ord_alias, $first_ord_col) = $first_order_by =~ /^ (?: ([^\.]+) \. )? ([^\.]+) $/x;

  $self->throw_exception(sprintf
    "Generic Subquery Limit order criteria can be only based on the root-source '%s'"
  . " (aliased as '%s')", $root_rsrc->source_name, $rs_attrs->{alias},
  ) if ($first_ord_alias and $first_ord_alias ne $rs_attrs->{alias});

  $first_ord_alias ||= $rs_attrs->{alias};

  $self->throw_exception(
    "Generic Subquery Limit first order criteria '$first_ord_col' must be unique"
  ) unless $root_rsrc->_identifying_column_set([$first_ord_col]);

  my ($stripped_sql, $in_sel, $out_sel, $alias_map, $extra_order_sel)
    = $self->_subqueried_limit_attrs ($sql, $rs_attrs);

  my $cmp_op = $direction eq 'desc' ? '>' : '<';
  my $count_tbl_alias = 'rownum__emulation';

  my $order_sql = $self->_order_by (delete $rs_attrs->{order_by});
  my $group_having_sql = $self->_parse_rs_attrs($rs_attrs);

  # add the order supplement (if any) as this is what will be used for the outer WHERE
  $in_sel .= ", $_" for keys %{$extra_order_sel||{}};

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

  return sprintf ("
SELECT $out_sel
  FROM (
    SELECT $in_sel ${stripped_sql}${group_having_sql}
  ) %s
WHERE ( SELECT COUNT(*) FROM %s %s WHERE %s $cmp_op %s ) $rownum_cond
$order_sql
  ", map { $self->_quote ($_) } (
    $rs_attrs->{alias},
    $root_tbl_name,
    $count_tbl_alias,
    "$count_tbl_alias.$first_ord_col",
    "$first_ord_alias.$first_ord_col",
  ));
}


# !!! THIS IS ALSO HORRIFIC !!! /me ashamed
#
# Generates inner/outer select lists for various limit dialects
# which result in one or more subqueries (e.g. RNO, Top, RowNum)
# Any non-root-table columns need to have their table qualifier
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

  # insulate from the multiple _recurse_fields calls below
  local $self->{select_bind};

  # correlate select and as, build selection index
  my (@sel, $in_sel_index);
  for my $i (0 .. $#{$rs_attrs->{select}}) {

    my $s = $rs_attrs->{select}[$i];
    my $sql_sel = $self->_recurse_fields ($s);
    my $sql_alias = (ref $s) eq 'HASH' ? $s->{-as} : undef;

    push @sel, {
      sql => $sql_sel,
      unquoted_sql => do {
        local $self->{quote_char};
        $self->_recurse_fields ($s);
      },
      as =>
        $sql_alias
          ||
        $rs_attrs->{as}[$i]
          ||
        $self->throw_exception("Select argument $i ($s) without corresponding 'as'")
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
    if (
      $node->{as} =~ / (?<! ^ $re_alias ) \. /x
        or
      $node->{unquoted_sql} =~ / (?<! ^ $re_alias ) $re_sep /x
    ) {
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
    $proto_sql,
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
  $fqcn =~ s/ \. /__/xg;
  return $fqcn;
}

1;

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

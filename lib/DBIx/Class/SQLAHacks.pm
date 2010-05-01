package # Hide from PAUSE
  DBIx::Class::SQLAHacks;

# This module is a subclass of SQL::Abstract::Limit and includes a number
# of DBIC-specific workarounds, not yet suitable for inclusion into the
# SQLA core

use base qw/SQL::Abstract::Limit/;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;
use Sub::Name();

BEGIN {
  # reinstall the carp()/croak() functions imported into SQL::Abstract
  # as Carp and Carp::Clan do not like each other much
  no warnings qw/redefine/;
  no strict qw/refs/;
  for my $f (qw/carp croak/) {

    my $orig = \&{"SQL::Abstract::$f"};
    *{"SQL::Abstract::$f"} = Sub::Name::subname "SQL::Abstract::$f" =>
      sub {
        if (Carp::longmess() =~ /DBIx::Class::SQLAHacks::[\w]+ .+? called \s at/x) {
          __PACKAGE__->can($f)->(@_);
        }
        else {
          goto $orig;
        }
      };
  }
}


# Tries to determine limit dialect.
#
sub new {
  my $self = shift->SUPER::new(@_);

  # This prevents the caching of $dbh in S::A::L, I believe
  # If limit_dialect is a ref (like a $dbh), go ahead and replace
  #   it with what it resolves to:
  $self->{limit_dialect} = $self->_find_syntax($self->{limit_dialect})
    if ref $self->{limit_dialect};

  $self;
}

# generate inner/outer select lists for various limit dialects
# which result in one or more subqueries (e.g. RNO, Top, RowNum)
# Any non-root-table columns need to have their table qualifier
# turned into a column name (otherwise names in subqueries clash
# and/or lose their source table)
sub _subqueried_selection {
  my ($self, $rs_attrs) = @_;

  croak 'Limit usable only in the context of DBIC (missing $rs_attrs)' unless $rs_attrs;

  # correlate select and as
  my @sel;
  for my $i (0 .. $#{$rs_attrs->{select}}) {
    my $s = $rs_attrs->{select}[$i];
    push @sel, {
      sql => $self->_recurse_fields ($s),
      unquoted_sql => do { local $self->{quote_char}; $self->_recurse_fields ($s) },
      as =>
        ( (ref $s) eq 'HASH' ? $s->{-as} : undef)
          ||
        $rs_attrs->{as}[$i]
          ||
        croak "Select argument $i ($s) without corresponding 'as'"
      ,
    };
  }

  my ($qsep, $qalias) = map { quotemeta $_ } (
    $self->name_sep || '.',
    $rs_attrs->{alias},
  );

  # re-alias and remove any name separators from aliases,
  # unless we are dealing with the current source alias
  # (which will transcend the subqueries and is necessary
  # for possible further chaining)
  my (@insel, @outsel);
  for my $node (@sel) {
    if (List::Util::first { $_ =~ / (?<! $qalias ) $qsep /x } ($node->{as}, $node->{unquoted_sql}) )  {
      $node->{as} =~ s/ $qsep /__/xg;
      push @insel, sprintf '%s AS %s', $node->{sql}, $self->_quote($node->{as});
      push @outsel, $self->_quote ($node->{as});
    }
    else {
      push @insel, $node->{sql};
      push @outsel, $self->_quote ($node->{as});
    }
  }

  return map { join (', ', @$_ ) } (\@insel, \@outsel);
}


# ANSI standard Limit/Offset implementation. DB2 and MSSQL use this
sub _RowNumberOver {
  my ($self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # mangle the input sql as we will be replacing the selector
  $sql =~ s/^ \s* SELECT \s+ .+? \s+ (?= \b FROM \b )//ix
    or croak "Unrecognizable SELECT: $sql";

  # get selectors
  my ($insel, $outsel) = $self->_subqueried_selection ($rs_attrs);

  # make up an order if none exists
  my $order_by = $self->_order_by(
    (delete $rs_attrs->{order_by}) || $self->_rno_default_order
  );

  # whatever is left of the order_by (only where is processed at this point)
  my $group_having = $self->_parse_rs_attrs($rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});

  my $idx_name = $self->_quote ('rno__row__index');

  $sql = sprintf (<<EOS, $offset + 1, $offset + $rows, );

SELECT $outsel FROM (
  SELECT $outsel, ROW_NUMBER() OVER($order_by ) AS $idx_name FROM (
    SELECT $insel ${sql}${group_having}
  ) $qalias
) $qalias WHERE $idx_name BETWEEN %d AND %d

EOS

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}

# some databases are happy with OVER (), some need OVER (ORDER BY (SELECT (1)) )
sub _rno_default_order {
  return undef;
}

# Informix specific limit, almost like LIMIT/OFFSET
sub _SkipFirst {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  $sql =~ s/^ \s* SELECT \s+ //ix
    or croak "Unrecognizable SELECT: $sql";

  return sprintf ('SELECT %s%s%s%s',
    $offset
      ? sprintf ('SKIP %d ', $offset)
      : ''
    ,
    sprintf ('FIRST %d ', $rows),
    $sql,
    $self->_parse_rs_attrs ($rs_attrs),
  );
}

# Firebird specific limit, reverse of _SkipFirst for Informix
sub _FirstSkip {
  my ($self, $sql, $rs_attrs, $rows, $offset) = @_;

  $sql =~ s/^ \s* SELECT \s+ //ix
    or croak "Unrecognizable SELECT: $sql";

  return sprintf ('SELECT %s%s%s%s',
    sprintf ('FIRST %d ', $rows),
    $offset
      ? sprintf ('SKIP %d ', $offset)
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

  my ($insel, $outsel) = $self->_subqueried_selection ($rs_attrs);

  my $qalias = $self->_quote ($rs_attrs->{alias});
  my $idx_name = $self->_quote ('rownum__index');
  my $order_group_having = $self->_parse_rs_attrs($rs_attrs);

  $sql = sprintf (<<EOS, $offset + 1, $offset + $rows, );

SELECT $outsel FROM (
  SELECT $outsel, ROWNUM $idx_name FROM (
    SELECT $insel ${sql}${order_group_having}
  ) $qalias
) $qalias WHERE $idx_name BETWEEN %d AND %d

EOS

  $sql =~ s/\s*\n\s*/ /g;   # easier to read in the debugger
  return $sql;
}

=begin
# Crappy Top based Limit/Offset support. Legacy from MSSQL.
sub _Top {
  my ( $self, $sql, $rs_attrs, $rows, $offset ) = @_;

  # mangle the input sql as we will be replacing the selector
  $sql =~ s/^ \s* SELECT \s+ .+? \s+ (?= \b FROM \b )//ix
    or croak "Unrecognizable SELECT: $sql";

  # get selectors
  my ($insel, $outsel) = $self->_subqueried_selection ($rs_attrs);

  # deal with order
  my $rs_alias = $rs_attrs->{alias};
  my $req_order = delete $rs_attrs->{order_by};
  my $name_sep = $self->name_sep || '.';

  # examine normalized version, collapses nesting
  my $limit_order = scalar $self->_order_by_chunks ($req_order)
    ? $req_order
    : [ map
      { join ('', $rs_alias, $name_sep, $_ ) }
      ( $rs_attrs->{_rsroot_source_handle}->resolve->primary_columns )
    ]
  ;

  my ( $order_by_inner, $order_by_outer ) = $self->_order_directions($limit_order);
  my $order_by_requested = $self->_order_by ($req_order);




  my $esc_name_sep = "\Q$name_sep\E";
  my $col_re = qr/ ^ (?: (.+) $esc_name_sep )? ([^$esc_name_sep]+) $ /x;

  my $quoted_rs_alias = $self->_quote ($rs_alias);

  # construct the new select lists, rename(alias) some columns if necessary
  my (@outer_select, @inner_select, %seen_names, %col_aliases, %outer_col_aliases);

  for (@{$rs_attrs->{select}}) {
    next if ref $_;
    my ($table, $orig_colname) = ( $_ =~ $col_re );
    next unless $table;
    $seen_names{$orig_colname}++;
  }

  for my $i (0 .. $#sql_select) {

    my $colsel_arg = $rs_attrs->{select}[$i];
    my $colsel_sql = $sql_select[$i];

    # this may or may not work (in case of a scalarref or something)
    my ($table, $orig_colname) = ( $colsel_arg =~ $col_re );

    my $quoted_alias;
    # do not attempt to understand non-scalar selects - alias numerically
    if (ref $colsel_arg) {
      $quoted_alias = $self->_quote ('column_' . (@inner_select + 1) );
    }
    # column name seen more than once - alias it
    elsif ($orig_colname &&
          ($seen_names{$orig_colname} && $seen_names{$orig_colname} > 1) ) {
      $quoted_alias = $self->_quote ("${table}__${orig_colname}");
    }

    # we did rename - make a record and adjust
    if ($quoted_alias) {
      # alias inner
      push @inner_select, "$colsel_sql AS $quoted_alias";

      # push alias to outer
      push @outer_select, $quoted_alias;

      # Any aliasing accumulated here will be considered
      # both for inner and outer adjustments of ORDER BY
      $self->__record_alias (
        \%col_aliases,
        $quoted_alias,
        $colsel_arg,
        $table ? $orig_colname : undef,
      );
    }

    # otherwise just leave things intact inside, and use the abbreviated one outside
    # (as we do not have table names anymore)
    else {
      push @inner_select, $colsel_sql;

      my $outer_quoted = $self->_quote ($orig_colname);  # it was not a duplicate so should just work
      push @outer_select, $outer_quoted;
      $self->__record_alias (
        \%outer_col_aliases,
        $outer_quoted,
        $colsel_arg,
        $table ? $orig_colname : undef,
      );
    }
  }

  my $outer_select = join (', ', @outer_select );
  my $inner_select = join (', ', @inner_select );

  %outer_col_aliases = (%outer_col_aliases, %col_aliases);




  # generate the rest
  my $grpby_having = $self->_parse_rs_attrs ($rs_attrs);

  # short circuit for counts - the ordering complexity is needless
  if ($rs_attrs->{-for_count_only}) {
    return "SELECT TOP $rows $inner_select $sql $grpby_having $order_by_outer";
  }

  # we can't really adjust the order_by columns, as introspection is lacking
  # resort to simple substitution
  for my $col (keys %outer_col_aliases) {
    for ($order_by_requested, $order_by_outer) {
      $_ =~ s/\s+$col\s+/ $outer_col_aliases{$col} /g;
    }
  }
  for my $col (keys %col_aliases) {
    $order_by_inner =~ s/\s+$col\s+/ $col_aliases{$col} /g;
  }


  my $inner_lim = $rows + $offset;

  $sql = "SELECT TOP $inner_lim $inner_select $sql $grpby_having $order_by_inner";

  if ($offset) {
    $sql = <<"SQL";

    SELECT TOP $rows $outer_select FROM
    (
      $sql
    ) $quoted_rs_alias
    $order_by_outer
SQL

  }

  if ($order_by_requested) {
    $sql = <<"SQL";

    SELECT $outer_select FROM
      ( $sql ) $quoted_rs_alias
    $order_by_requested
SQL

  }

  $sql =~ s/\s*\n\s*/ /g; # parsing out multiline statements is harder than a single line
  return $sql;
}
=cut

# While we're at it, this should make LIMIT queries more efficient,
#  without digging into things too deeply
sub _find_syntax {
  my ($self, $syntax) = @_;
  return $self->{_cached_syntax} ||= $self->SUPER::_find_syntax($syntax);
}

# Quotes table names, handles "limit" dialects (e.g. where rownum between x and
# y)
sub select {
  my ($self, $table, $fields, $where, $rs_attrs, @rest) = @_;

  $self->{"${_}_bind"} = [] for (qw/having from order/);

  if (not ref($table) or ref($table) eq 'SCALAR') {
    $table = $self->_quote($table);
  }

  local $self->{rownum_hack_count} = 1
    if (defined $rest[0] && $self->{limit_dialect} eq 'RowNum');
  @rest = (-1) unless defined $rest[0];
  croak "LIMIT 0 Does Not Compute" if $rest[0] == 0;
    # and anyway, SQL::Abstract::Limit will cause a barf if we don't first

  my ($sql, @where_bind) = $self->SUPER::select(
    $table, $self->_recurse_fields($fields), $where, $rs_attrs, @rest
  );
  return wantarray ? ($sql, @{$self->{from_bind}}, @where_bind, @{$self->{having_bind}}, @{$self->{order_bind}} ) : $sql;
}

# Quotes table names, and handles default inserts
sub insert {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table);

  # SQLA will emit INSERT INTO $table ( ) VALUES ( )
  # which is sadly understood only by MySQL. Change default behavior here,
  # until SQLA2 comes with proper dialect support
  if (! $_[0] or (ref $_[0] eq 'HASH' and !keys %{$_[0]} ) ) {
    my $sql = "INSERT INTO ${table} DEFAULT VALUES";

    if (my $ret = ($_[1]||{})->{returning} ) {
      $sql .= $self->_insert_returning ($ret);
    }

    return $sql;
  }

  $self->SUPER::insert($table, @_);
}

# Just quotes table names.
sub update {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table);
  $self->SUPER::update($table, @_);
}

# Just quotes table names.
sub delete {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table);
  $self->SUPER::delete($table, @_);
}

sub _emulate_limit {
  my $self = shift;
  # my ( $syntax, $sql, $order, $rows, $offset ) = @_;

  if ($_[3] == -1) {
    return $_[1] . $self->_parse_rs_attrs($_[2]);
  } else {
    return $self->SUPER::_emulate_limit(@_);
  }
}

sub _recurse_fields {
  my ($self, $fields) = @_;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    return join(', ', map { $self->_recurse_fields($_) } @$fields);
  }
  elsif ($ref eq 'HASH') {
    my %hash = %$fields;  # shallow copy

    my $as = delete $hash{-as};   # if supplied

    my ($func, $args, @toomany) = %hash;

    # there should be only one pair
    if (@toomany) {
      croak "Malformed select argument - too many keys in hash: " . join (',', keys %$fields );
    }

    if (lc ($func) eq 'distinct' && ref $args eq 'ARRAY' && @$args > 1) {
      croak (
        'The select => { distinct => ... } syntax is not supported for multiple columns.'
       .' Instead please use { group_by => [ qw/' . (join ' ', @$args) . '/ ] }'
       .' or { select => [ qw/' . (join ' ', @$args) . '/ ], distinct => 1 }'
      );
    }

    my $select = sprintf ('%s( %s )%s',
      $self->_sqlcase($func),
      $self->_recurse_fields($args),
      $as
        ? sprintf (' %s %s', $self->_sqlcase('as'), $self->_quote ($as) )
        : ''
    );

    return $select;
  }
  # Is the second check absolutely necessary?
  elsif ( $ref eq 'REF' and ref($$fields) eq 'ARRAY' ) {
    return $self->_fold_sqlbind( $fields );
  }
  else {
    croak($ref . qq{ unexpected in _recurse_fields()})
  }
}

my $for_syntax = {
  update => 'FOR UPDATE',
  shared => 'FOR SHARE',
};

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

  if (my $g = $self->_recurse_fields($arg->{group_by}, { no_rownum_hack => 1 }) ) {
    $sql .= $self->_sqlcase(' group by ') . $g;
  }

  if (defined $arg->{having}) {
    my ($frag, @bind) = $self->_recurse_where($arg->{having});
    push(@{$self->{having_bind}}, @bind);
    $sql .= $self->_sqlcase(' having ') . $frag;
  }

  if (defined $arg->{order_by}) {
    $sql .= $self->_order_by ($arg->{order_by});
  }

  if (my $for = $arg->{for}) {
    $sql .= " $for_syntax->{$for}" if $for_syntax->{$for};
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
    my ($sql, @bind) = $self->SUPER::_order_by ($arg);
    push @{$self->{order_bind}}, @bind;
    return $sql;
  }
}

sub _order_directions {
  my ($self, $order) = @_;

  # strip bind values - none of the current _order_directions users support them
  return $self->SUPER::_order_directions( [ map
    { ref $_ ? $_->[0] : $_ }
    $self->_order_by_chunks ($order)
  ]);
}

sub _table {
  my ($self, $from) = @_;
  if (ref $from eq 'ARRAY') {
    return $self->_recurse_from(@$from);
  } elsif (ref $from eq 'HASH') {
    return $self->_make_as($from);
  } else {
    return $from; # would love to quote here but _table ends up getting called
                  # twice during an ->select without a limit clause due to
                  # the way S::A::Limit->select works. should maybe consider
                  # bypassing this and doing S::A::select($self, ...) in
                  # our select method above. meantime, quoting shims have
                  # been added to select/insert/update/delete here
  }
}

sub _generate_join_clause {
    my ($self, $join_type) = @_;

    return sprintf ('%s JOIN ',
      $join_type ?  ' ' . uc($join_type) : ''
    );
}

sub _recurse_from {
  my ($self, $from, @join) = @_;
  my @sqlf;
  push(@sqlf, $self->_make_as($from));
  foreach my $j (@join) {
    my ($to, $on) = @$j;


    # check whether a join type exists
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    my $join_type;
    if (ref($to_jt) eq 'HASH' and defined($to_jt->{-join_type})) {
      $join_type = $to_jt->{-join_type};
      $join_type =~ s/^\s+ | \s+$//xg;
    }

    $join_type = $self->{_default_jointype} if not defined $join_type;

    push @sqlf, $self->_generate_join_clause( $join_type );

    if (ref $to eq 'ARRAY') {
      push(@sqlf, '(', $self->_recurse_from(@$to), ')');
    } else {
      push(@sqlf, $self->_make_as($to));
    }
    push(@sqlf, ' ON ', $self->_join_condition($on));
  }
  return join('', @sqlf);
}

sub _fold_sqlbind {
  my ($self, $sqlbind) = @_;

  my @sqlbind = @$$sqlbind; # copy
  my $sql = shift @sqlbind;
  push @{$self->{from_bind}}, @sqlbind;

  return $sql;
}

sub _make_as {
  my ($self, $from) = @_;
  return join(' ', map { (ref $_ eq 'SCALAR' ? $$_
                        : ref $_ eq 'REF'    ? $self->_fold_sqlbind($_)
                        : $self->_quote($_))
                       } reverse each %{$self->_skip_options($from)});
}

sub _skip_options {
  my ($self, $hash) = @_;
  my $clean_hash = {};
  $clean_hash->{$_} = $hash->{$_}
    for grep {!/^-/} keys %$hash;
  return $clean_hash;
}

sub _join_condition {
  my ($self, $cond) = @_;
  if (ref $cond eq 'HASH') {
    my %j;
    for (keys %$cond) {
      my $v = $cond->{$_};
      if (ref $v) {
        croak (ref($v) . qq{ reference arguments are not supported in JOINS - try using \"..." instead'})
            if ref($v) ne 'SCALAR';
        $j{$_} = $v;
      }
      else {
        my $x = '= '.$self->_quote($v); $j{$_} = \$x;
      }
    };
    return scalar($self->_recurse_where(\%j));
  } elsif (ref $cond eq 'ARRAY') {
    return join(' OR ', map { $self->_join_condition($_) } @$cond);
  } else {
    die "Can't handle this yet!";
  }
}

sub limit_dialect {
    my $self = shift;
    if (@_) {
      $self->{limit_dialect} = shift;
      undef $self->{_cached_syntax};
    }
    return $self->{limit_dialect};
}

# Set to an array-ref to specify separate left and right quotes for table names.
# A single scalar is equivalen to [ $char, $char ]
sub quote_char {
    my $self = shift;
    $self->{quote_char} = shift if @_;
    return $self->{quote_char};
}

# Character separating quoted table names.
sub name_sep {
    my $self = shift;
    $self->{name_sep} = shift if @_;
    return $self->{name_sep};
}

1;

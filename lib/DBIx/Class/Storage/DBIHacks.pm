package   #hide from PAUSE
  DBIx::Class::Storage::DBIHacks;

#
# This module contains code that should never have seen the light of day,
# does not belong in the Storage, or is otherwise unfit for public
# display. The arrival of SQLA2 should immediately oboslete 90% of this
#

use strict;
use warnings;

use base 'DBIx::Class::Storage';
use mro 'c3';

use Carp::Clan qw/^DBIx::Class/;

#
# This is the code producing joined subqueries like:
# SELECT me.*, other.* FROM ( SELECT me.* FROM ... ) JOIN other ON ... 
#
sub _adjust_select_args_for_complex_prefetch {
  my ($self, $from, $select, $where, $attrs) = @_;

  $self->throw_exception ('Nothing to prefetch... how did we get here?!')
    if not @{$attrs->{_prefetch_select}};

  $self->throw_exception ('Complex prefetches are not supported on resultsets with a custom from attribute')
    if (ref $from ne 'ARRAY' || ref $from->[0] ne 'HASH' || ref $from->[1] ne 'ARRAY');


  # generate inner/outer attribute lists, remove stuff that doesn't apply
  my $outer_attrs = { %$attrs };
  delete $outer_attrs->{$_} for qw/where bind rows offset group_by having/;

  my $inner_attrs = { %$attrs };
  delete $inner_attrs->{$_} for qw/for collapse _prefetch_select _collapse_order_by select as/;


  # bring over all non-collapse-induced order_by into the inner query (if any)
  # the outer one will have to keep them all
  delete $inner_attrs->{order_by};
  if (my $ord_cnt = @{$outer_attrs->{order_by}} - @{$outer_attrs->{_collapse_order_by}} ) {
    $inner_attrs->{order_by} = [
      @{$outer_attrs->{order_by}}[ 0 .. $ord_cnt - 1]
    ];
  }


  # generate the inner/outer select lists
  # for inside we consider only stuff *not* brought in by the prefetch
  # on the outside we substitute any function for its alias
  my $outer_select = [ @$select ];
  my $inner_select = [];
  for my $i (0 .. ( @$outer_select - @{$outer_attrs->{_prefetch_select}} - 1) ) {
    my $sel = $outer_select->[$i];

    if (ref $sel eq 'HASH' ) {
      $sel->{-as} ||= $attrs->{as}[$i];
      $outer_select->[$i] = join ('.', $attrs->{alias}, ($sel->{-as} || "inner_column_$i") );
    }

    push @$inner_select, $sel;
  }

  # normalize a copy of $from, so it will be easier to work with further
  # down (i.e. promote the initial hashref to an AoH)
  $from = [ @$from ];
  $from->[0] = [ $from->[0] ];
  my %original_join_info = map { $_->[0]{-alias} => $_->[0] } (@$from);


  # decide which parts of the join will remain in either part of
  # the outer/inner query

  # First we compose a list of which aliases are used in restrictions
  # (i.e. conditions/order/grouping/etc). Since we do not have
  # introspectable SQLA, we fall back to ugly scanning of raw SQL for
  # WHERE, and for pieces of ORDER BY in order to determine which aliases
  # need to appear in the resulting sql.
  # It may not be very efficient, but it's a reasonable stop-gap
  # Also unqualified column names will not be considered, but more often
  # than not this is actually ok
  #
  # In the same loop we enumerate part of the selection aliases, as
  # it requires the same sqla hack for the time being
  my ($restrict_aliases, $select_aliases, $prefetch_aliases);
  {
    # produce stuff unquoted, so it can be scanned
    my $sql_maker = $self->sql_maker;
    local $sql_maker->{quote_char};
    my $sep = $self->_sql_maker_opts->{name_sep} || '.';
    $sep = "\Q$sep\E";

    my $non_prefetch_select_sql = $sql_maker->_recurse_fields ($inner_select);
    my $prefetch_select_sql = $sql_maker->_recurse_fields ($outer_attrs->{_prefetch_select});
    my $where_sql = $sql_maker->where ($where);
    my $group_by_sql = $sql_maker->_order_by({
      map { $_ => $inner_attrs->{$_} } qw/group_by having/
    });
    my @non_prefetch_order_by_chunks = (map
      { ref $_ ? $_->[0] : $_ }
      $sql_maker->_order_by_chunks ($inner_attrs->{order_by})
    );


    for my $alias (keys %original_join_info) {
      my $seen_re = qr/\b $alias $sep/x;

      for my $piece ($where_sql, $group_by_sql, @non_prefetch_order_by_chunks ) {
        if ($piece =~ $seen_re) {
          $restrict_aliases->{$alias} = 1;
        }
      }

      if ($non_prefetch_select_sql =~ $seen_re) {
          $select_aliases->{$alias} = 1;
      }

      if ($prefetch_select_sql =~ $seen_re) {
          $prefetch_aliases->{$alias} = 1;
      }

    }
  }

  # Add any non-left joins to the restriction list (such joins are indeed restrictions)
  for my $j (values %original_join_info) {
    my $alias = $j->{-alias} or next;
    $restrict_aliases->{$alias} = 1 if (
      (not $j->{-join_type})
        or
      ($j->{-join_type} !~ /^left (?: \s+ outer)? $/xi)
    );
  }

  # mark all join parents as mentioned
  # (e.g.  join => { cds => 'tracks' } - tracks will need to bring cds too )
  for my $collection ($restrict_aliases, $select_aliases) {
    for my $alias (keys %$collection) {
      $collection->{$_} = 1
        for (@{ $original_join_info{$alias}{-join_path} || [] });
    }
  }

  # construct the inner $from for the subquery
  my %inner_joins = (map { %{$_ || {}} } ($restrict_aliases, $select_aliases) );
  my @inner_from;
  for my $j (@$from) {
    push @inner_from, $j if $inner_joins{$j->[0]{-alias}};
  }

  # if a multi-type join was needed in the subquery ("multi" is indicated by
  # presence in {collapse}) - add a group_by to simulate the collapse in the subq
  unless ($inner_attrs->{group_by}) {
    for my $alias (keys %inner_joins) {

      # the dot comes from some weirdness in collapse
      # remove after the rewrite
      if ($attrs->{collapse}{".$alias"}) {
        $inner_attrs->{group_by} ||= $inner_select;
        last;
      }
    }
  }

  # demote the inner_from head
  $inner_from[0] = $inner_from[0][0];

  # generate the subquery
  my $subq = $self->_select_args_to_query (
    \@inner_from,
    $inner_select,
    $where,
    $inner_attrs,
  );

  my $subq_joinspec = {
    -alias => $attrs->{alias},
    -source_handle => $inner_from[0]{-source_handle},
    $attrs->{alias} => $subq,
  };

  # Generate the outer from - this is relatively easy (really just replace
  # the join slot with the subquery), with a major caveat - we can not
  # join anything that is non-selecting (not part of the prefetch), but at
  # the same time is a multi-type relationship, as it will explode the result.
  #
  # There are two possibilities here
  # - either the join is non-restricting, in which case we simply throw it away
  # - it is part of the restrictions, in which case we need to collapse the outer
  #   result by tackling yet another group_by to the outside of the query

  # so first generate the outer_from, up to the substitution point
  my @outer_from;
  while (my $j = shift @$from) {
    if ($j->[0]{-alias} eq $attrs->{alias}) { # time to swap
      push @outer_from, [
        $subq_joinspec,
        @{$j}[1 .. $#$j],
      ];
      last; # we'll take care of what's left in $from below
    }
    else {
      push @outer_from, $j;
    }
  }

  # see what's left - throw away if not selecting/restricting
  # also throw in a group_by if restricting to guard against
  # cross-join explosions
  #
  while (my $j = shift @$from) {
    my $alias = $j->[0]{-alias};

    if ($select_aliases->{$alias} || $prefetch_aliases->{$alias}) {
      push @outer_from, $j;
    }
    elsif ($restrict_aliases->{$alias}) {
      push @outer_from, $j;

      # FIXME - this should be obviated by SQLA2, as I'll be able to 
      # have restrict_inner and restrict_outer... or something to that
      # effect... I think...

      # FIXME2 - I can't find a clean way to determine if a particular join
      # is a multi - instead I am just treating everything as a potential
      # explosive join (ribasushi)
      #
      # if (my $handle = $j->[0]{-source_handle}) {
      #   my $rsrc = $handle->resolve;
      #   ... need to bail out of the following if this is not a multi,
      #       as it will be much easier on the db ...

          $outer_attrs->{group_by} ||= $outer_select;
      # }
    }
  }

  # demote the outer_from head
  $outer_from[0] = $outer_from[0][0];

  # This is totally horrific - the $where ends up in both the inner and outer query
  # Unfortunately not much can be done until SQLA2 introspection arrives, and even
  # then if where conditions apply to the *right* side of the prefetch, you may have
  # to both filter the inner select (e.g. to apply a limit) and then have to re-filter
  # the outer select to exclude joins you didin't want in the first place
  #
  # OTOH it can be seen as a plus: <ash> (notes that this query would make a DBA cry ;)
  return (\@outer_from, $outer_select, $where, $outer_attrs);
}

sub _resolve_ident_sources {
  my ($self, $ident) = @_;

  my $alias2source = {};
  my $rs_alias;

  # the reason this is so contrived is that $ident may be a {from}
  # structure, specifying multiple tables to join
  if ( Scalar::Util::blessed($ident) && $ident->isa("DBIx::Class::ResultSource") ) {
    # this is compat mode for insert/update/delete which do not deal with aliases
    $alias2source->{me} = $ident;
    $rs_alias = 'me';
  }
  elsif (ref $ident eq 'ARRAY') {

    for (@$ident) {
      my $tabinfo;
      if (ref $_ eq 'HASH') {
        $tabinfo = $_;
        $rs_alias = $tabinfo->{-alias};
      }
      if (ref $_ eq 'ARRAY' and ref $_->[0] eq 'HASH') {
        $tabinfo = $_->[0];
      }

      $alias2source->{$tabinfo->{-alias}} = $tabinfo->{-source_handle}->resolve
        if ($tabinfo->{-source_handle});
    }
  }

  return ($alias2source, $rs_alias);
}

# Takes $ident, \@column_names
#
# returns { $column_name => \%column_info, ... }
# also note: this adds -result_source => $rsrc to the column info
#
# If no columns_names are supplied returns info about *all* columns
# for all sources
sub _resolve_column_info {
  my ($self, $ident, $colnames) = @_;
  my ($alias2src, $root_alias) = $self->_resolve_ident_sources($ident);

  my $sep = $self->_sql_maker_opts->{name_sep} || '.';
  my $qsep = quotemeta $sep;

  my (%return, %seen_cols, @auto_colnames);

  # compile a global list of column names, to be able to properly
  # disambiguate unqualified column names (if at all possible)
  for my $alias (keys %$alias2src) {
    my $rsrc = $alias2src->{$alias};
    for my $colname ($rsrc->columns) {
      push @{$seen_cols{$colname}}, $alias;
      push @auto_colnames, "$alias$sep$colname" unless $colnames;
    }
  }

  $colnames ||= [
    @auto_colnames,
    grep { @{$seen_cols{$_}} == 1 } (keys %seen_cols),
  ];

  COLUMN:
  foreach my $col (@$colnames) {
    my ($alias, $colname) = $col =~ m/^ (?: ([^$qsep]+) $qsep)? (.+) $/x;

    unless ($alias) {
      # see if the column was seen exactly once (so we know which rsrc it came from)
      if ($seen_cols{$colname} and @{$seen_cols{$colname}} == 1) {
        $alias = $seen_cols{$colname}[0];
      }
      else {
        next COLUMN;
      }
    }

    my $rsrc = $alias2src->{$alias};
    $return{$col} = $rsrc && {
      %{$rsrc->column_info($colname)},
      -result_source => $rsrc,
      -source_alias => $alias,
    };
  }

  return \%return;
}

# The DBIC relationship chaining implementation is pretty simple - every
# new related_relationship is pushed onto the {from} stack, and the {select}
# window simply slides further in. This means that when we count somewhere
# in the middle, we got to make sure that everything in the join chain is an
# actual inner join, otherwise the count will come back with unpredictable
# results (a resultset may be generated with _some_ rows regardless of if
# the relation which the $rs currently selects has rows or not). E.g.
# $artist_rs->cds->count - normally generates:
# SELECT COUNT( * ) FROM artist me LEFT JOIN cd cds ON cds.artist = me.artistid
# which actually returns the number of artists * (number of cds || 1)
#
# So what we do here is crawl {from}, determine if the current alias is at
# the top of the stack, and if not - make sure the chain is inner-joined down
# to the root.
#
sub _straight_join_to_node {
  my ($self, $from, $alias) = @_;

  # subqueries and other oddness are naturally not supported
  return $from if (
    ref $from ne 'ARRAY'
      ||
    @$from <= 1
      ||
    ref $from->[0] ne 'HASH'
      ||
    ! $from->[0]{-alias}
      ||
    $from->[0]{-alias} eq $alias  # this last bit means $alias is the head of $from - nothing to do
  );

  # find the current $alias in the $from structure
  my $switch_branch;
  JOINSCAN:
  for my $j (@{$from}[1 .. $#$from]) {
    if ($j->[0]{-alias} eq $alias) {
      $switch_branch = $j->[0]{-join_path};
      last JOINSCAN;
    }
  }

  # something else went quite wrong
  return $from unless $switch_branch;

  # So it looks like we will have to switch some stuff around.
  # local() is useless here as we will be leaving the scope
  # anyway, and deep cloning is just too fucking expensive
  # So replace the first hashref in the node arrayref manually 
  my @new_from = ($from->[0]);
  my $sw_idx = { map { $_ => 1 } @$switch_branch };

  for my $j (@{$from}[1 .. $#$from]) {
    my $jalias = $j->[0]{-alias};

    if ($sw_idx->{$jalias}) {
      my %attrs = %{$j->[0]};
      delete $attrs{-join_type};
      push @new_from, [
        \%attrs,
        @{$j}[ 1 .. $#$j ],
      ];
    }
    else {
      push @new_from, $j;
    }
  }

  return \@new_from;
}

# Most databases do not allow aliasing of tables in UPDATE/DELETE. Thus
# a condition containing 'me' or other table prefixes will not work
# at all. What this code tries to do (badly) is introspect the condition
# and remove all column qualifiers. If it bails out early (returns undef)
# the calling code should try another approach (e.g. a subquery)
sub _strip_cond_qualifiers {
  my ($self, $where) = @_;

  my $cond = {};

  # No-op. No condition, we're updating/deleting everything
  return $cond unless $where;

  if (ref $where eq 'ARRAY') {
    $cond = [
      map {
        my %hash;
        foreach my $key (keys %{$_}) {
          $key =~ /([^.]+)$/;
          $hash{$1} = $_->{$key};
        }
        \%hash;
      } @$where
    ];
  }
  elsif (ref $where eq 'HASH') {
    if ( (keys %$where) == 1 && ( (keys %{$where})[0] eq '-and' )) {
      $cond->{-and} = [];
      my @cond = @{$where->{-and}};
       for (my $i = 0; $i < @cond; $i++) {
        my $entry = $cond[$i];
        my $hash;
        if (ref $entry eq 'HASH') {
          $hash = $self->_strip_cond_qualifiers($entry);
        }
        else {
          $entry =~ /([^.]+)$/;
          $hash->{$1} = $cond[++$i];
        }
        push @{$cond->{-and}}, $hash;
      }
    }
    else {
      foreach my $key (keys %$where) {
        $key =~ /([^.]+)$/;
        $cond->{$1} = $where->{$key};
      }
    }
  }
  else {
    return undef;
  }

  return $cond;
}


1;

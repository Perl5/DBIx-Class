package   #hide from PAUSE
  DBIx::Class::Storage::DBIHacks;

#
# This module contains code that should never have seen the light of day,
# does not belong in the Storage, or is otherwise unfit for public
# display. The arrival of SQLA2 should immediately obsolete 90% of this
#

use strict;
use warnings;

use base 'DBIx::Class::Storage';
use mro 'c3';

use List::Util 'first';
use Scalar::Util 'blessed';
use Sub::Name 'subname';
use namespace::clean;

#
# This code will remove non-selecting/non-restricting joins from
# {from} specs, aiding the RDBMS query optimizer
#
sub _prune_unused_joins {
  my $self = shift;
  my ($from, $select, $where, $attrs) = @_;

  return $from unless $self->_use_join_optimizer;

  if (ref $from ne 'ARRAY' || ref $from->[0] ne 'HASH' || ref $from->[1] ne 'ARRAY') {
    return $from;   # only standard {from} specs are supported
  }

  my $aliastypes = $self->_resolve_aliastypes_from_select_args(@_);

  # don't care
  delete $aliastypes->{joining};

  # a grouped set will not be affected by amount of rows. Thus any
  # {multiplying} joins can go
  delete $aliastypes->{multiplying}
    if $attrs->{_force_prune_multiplying_joins} or $attrs->{group_by};

  my @newfrom = $from->[0]; # FROM head is always present

  my %need_joins;

  for (values %$aliastypes) {
    # add all requested aliases
    $need_joins{$_} = 1 for keys %$_;

    # add all their parents (as per joinpath which is an AoH { table => alias })
    $need_joins{$_} = 1 for map { values %$_ } map { @{$_->{-parents}} } values %$_;
  }

  for my $j (@{$from}[1..$#$from]) {
    push @newfrom, $j if (
      (! $j->[0]{-alias}) # legacy crap
        ||
      $need_joins{$j->[0]{-alias}}
    );
  }

  return \@newfrom;
}

#
# This is the code producing joined subqueries like:
# SELECT me.*, other.* FROM ( SELECT me.* FROM ... ) JOIN other ON ...
#
sub _adjust_select_args_for_complex_prefetch {
  my ($self, $from, $select, $where, $attrs) = @_;

  $self->throw_exception ('Complex prefetches are not supported on resultsets with a custom from attribute')
    if (ref $from ne 'ARRAY' || ref $from->[0] ne 'HASH' || ref $from->[1] ne 'ARRAY');

  my $root_alias = $attrs->{alias};

  # generate inner/outer attribute lists, remove stuff that doesn't apply
  my $outer_attrs = { %$attrs };
  delete $outer_attrs->{$_} for qw/where bind rows offset group_by _grouped_by_distinct having/;

  my $inner_attrs = { %$attrs };
  delete $inner_attrs->{$_} for qw/from for collapse select as _related_results_construction/;

  # there is no point of ordering the insides if there is no limit
  delete $inner_attrs->{order_by} if (
    delete $inner_attrs->{_order_is_artificial}
      or
    ! $inner_attrs->{rows}
  );

  # generate the inner/outer select lists
  # for inside we consider only stuff *not* brought in by the prefetch
  # on the outside we substitute any function for its alias
  my $outer_select = [ @$select ];
  my $inner_select;

  my ($root_node, $root_node_offset);

  for my $i (0 .. $#$from) {
    my $node = $from->[$i];
    my $h = (ref $node eq 'HASH')                                ? $node
          : (ref $node  eq 'ARRAY' and ref $node->[0] eq 'HASH') ? $node->[0]
          : next
    ;

    if ( ($h->{-alias}||'') eq $root_alias and $h->{-rsrc} ) {
      $root_node = $h;
      $root_node_offset = $i;
      last;
    }
  }

  $self->throw_exception ('Complex prefetches are not supported on resultsets with a custom from attribute')
    unless $root_node;

  # use the heavy duty resolver to take care of aliased/nonaliased naming
  my $colinfo = $self->_resolve_column_info($from);
  my $selected_root_columns;

  for my $i (0 .. $#$outer_select) {
    my $sel = $outer_select->[$i];

    next if (
      $colinfo->{$sel} and $colinfo->{$sel}{-source_alias} ne $root_alias
    );

    if (ref $sel eq 'HASH' ) {
      $sel->{-as} ||= $attrs->{as}[$i];
      $outer_select->[$i] = join ('.', $root_alias, ($sel->{-as} || "inner_column_$i") );
    }
    elsif (! ref $sel and my $ci = $colinfo->{$sel}) {
      $selected_root_columns->{$ci->{-colname}} = 1;
    }

    push @$inner_select, $sel;

    push @{$inner_attrs->{as}}, $attrs->{as}[$i];
  }

  # We will need to fetch all native columns in the inner subquery, which may
  # be a part of an *outer* join condition, or an order_by (which needs to be
  # preserved outside)
  # We can not just fetch everything because a potential has_many restricting
  # join collapse *will not work* on heavy data types.
  my $connecting_aliastypes = $self->_resolve_aliastypes_from_select_args(
    [grep { ref($_) eq 'ARRAY' or ref($_) eq 'HASH' } @{$from}[$root_node_offset .. $#$from]],
    [],
    $where,
    $inner_attrs
  );

  for (sort map { keys %{$_->{-seen_columns}||{}} } map { values %$_ } values %$connecting_aliastypes) {
    my $ci = $colinfo->{$_} or next;
    if (
      $ci->{-source_alias} eq $root_alias
        and
      ! $selected_root_columns->{$ci->{-colname}}++
    ) {
      # adding it to both to keep limits not supporting dark selectors happy
      push @$inner_select, $ci->{-fq_colname};
      push @{$inner_attrs->{as}}, $ci->{-fq_colname};
    }
  }

  # construct the inner $from and lock it in a subquery
  # we need to prune first, because this will determine if we need a group_by below
  # throw away all non-selecting, non-restricting multijoins
  # (since we def. do not care about multiplication those inside the subquery)
  my $inner_subq = do {

    # must use it here regardless of user requests
    local $self->{_use_join_optimizer} = 1;

    # throw away multijoins since we def. do not care about those inside the subquery
    my $inner_from = $self->_prune_unused_joins ($from, $inner_select, $where, {
      %$inner_attrs, _force_prune_multiplying_joins => 1
    });

    my $inner_aliastypes =
      $self->_resolve_aliastypes_from_select_args( $inner_from, $inner_select, $where, $inner_attrs );

    # uh-oh a multiplier (which is not us) left in, this is a problem
    if (
      $inner_aliastypes->{multiplying}
        and
      !$inner_aliastypes->{grouping}  # if there are groups - assume user knows wtf they are up to
        and
      my @multipliers = grep { $_ ne $root_alias } keys %{$inner_aliastypes->{multiplying}}
    ) {

      # if none of the multipliers came from an order_by (guaranteed to have been combined
      # with a limit) - easy - just slap a group_by to simulate a collape and be on our way
      if (
        ! $inner_aliastypes->{ordering}
          or
        ! first { $inner_aliastypes->{ordering}{$_} } @multipliers
      ) {

        my $unprocessed_order_chunks;
        ($inner_attrs->{group_by}, $unprocessed_order_chunks) = $self->_group_over_selection (
          $inner_from, $inner_select, $inner_attrs->{order_by}
        );

        $self->throw_exception (
          'A required group_by clause could not be constructed automatically due to a complex '
        . 'order_by criteria. Either order_by columns only (no functions) or construct a suitable '
        . 'group_by by hand'
        )  if $unprocessed_order_chunks;
      }
      else {
        # We need to order by external columns and group at the same time
        # so we can calculate the proper limit
        # This doesn't really make sense in SQL, however from DBICs point
        # of view is rather valid (order the leftmost objects by whatever
        # criteria and get the offset/rows many). There is a way around
        # this however in SQL - we simply tae the direction of each piece
        # of the foreign order and convert them to MIN(X) for ASC or MAX(X)
        # for DESC, and group_by the root columns. The end result should be
        # exactly what we expect

        # FIXME REMOVE LATER - (just a sanity check)
        if (defined ( my $impostor = first
          { $_ ne $root_alias }
          keys %{ $inner_aliastypes->{selecting} }
        ) ) {
          $self->throw_exception(sprintf
            'Unexpected inner selection during complex prefetch (%s)...',
            join ', ', keys %{ $inner_aliastypes->{joining}{$impostor}{-seen_columns} || {} }
          );
        }

        # supplement the main selection with pks if not already there,
        # as they will have to be a part of the group_by to colapse
        # things properly
        my $cur_sel = { map { $_ => 1 } @$inner_select };

        my @pks = map { "$root_alias.$_" } $root_node->{-rsrc}->primary_columns
          or $self->throw_exception( sprintf
            'Unable to perform complex limited prefetch off %s without declared primary key',
            $root_node->{-rsrc}->source_name,
          );
        for my $col (@pks) {
          push @$inner_select, $col
            unless $cur_sel->{$col}++;
        }

        # wrap any part of the order_by that "responds" to an ordering alias
        # into a MIN/MAX
        # FIXME - this code is a joke, will need to be completely rewritten in
        # the DQ branch. But I need to push a POC here, otherwise the
        # pesky tests won't pass
        my $sql_maker = $self->sql_maker;
        my ($lquote, $rquote, $sep) = map { quotemeta $_ } ($sql_maker->_quote_chars, $sql_maker->name_sep);
        my $own_re = qr/ $lquote \Q$root_alias\E $rquote $sep | \b \Q$root_alias\E $sep /x;
        my @order_chunks = map { ref $_ eq 'ARRAY' ? $_ : [ $_ ] } $sql_maker->_order_by_chunks($attrs->{order_by});
        my @new_order = map { \$_ } @order_chunks;
        my $inner_columns_info = $self->_resolve_column_info($inner_from);

        # loop through and replace stuff that is not "ours" with a min/max func
        # everything is a literal at this point, since we are likely properly
        # quoted and stuff
        for my $i (0 .. $#new_order) {
          my $chunk = $order_chunks[$i][0];

          # skip ourselves
          next if $chunk =~ $own_re;

          ($chunk, my $is_desc) = $sql_maker->_split_order_chunk($chunk);

          # maybe our own unqualified column
          my $ord_bit = (
            $lquote and $sep and $chunk =~ /^ $lquote ([^$sep]+) $rquote $/x
          ) ? $1 : $chunk;

          next if (
            $ord_bit
              and
            $inner_columns_info->{$ord_bit}
              and
            $inner_columns_info->{$ord_bit}{-source_alias} eq $root_alias
          );

          $new_order[$i] = \[
            sprintf(
              '%s(%s)%s',
              ($is_desc ? 'MAX' : 'MIN'),
              $chunk,
              ($is_desc ? ' DESC' : ''),
            ),
            @ {$order_chunks[$i]} [ 1 .. $#{$order_chunks[$i]} ]
          ];
        }

        $inner_attrs->{order_by} = \@new_order;

        # do not care about leftovers here - it will be all the functions
        # we just created
        ($inner_attrs->{group_by}) = $self->_group_over_selection (
          $inner_from, $inner_select, $inner_attrs->{order_by}
        );
      }
    }

    # we already optimized $inner_from above
    # and already local()ized
    $self->{_use_join_optimizer} = 0;

    # generate the subquery
    $self->_select_args_to_query (
      $inner_from,
      $inner_select,
      $where,
      $inner_attrs,
    );
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

  # work on a shallow copy
  $from = [ @$from ];

  my @outer_from;

  # we may not be the head
  if ($root_node_offset) {
    # first generate the outer_from, up to the substitution point
    @outer_from = splice @$from, 0, $root_node_offset;

    push @outer_from, [
      {
        -alias => $root_alias,
        -rsrc => $root_node->{-rsrc},
        $root_alias => $inner_subq,
      },
      @{$from->[0]}[1 .. $#{$from->[0]}],
    ];
  }
  else {
    @outer_from = {
      -alias => $root_alias,
      -rsrc => $root_node->{-rsrc},
      $root_alias => $inner_subq,
    };
  }

  shift @$from; # it's replaced in @outer_from already

  # scan the *remaining* from spec against different attributes, and see which joins are needed
  # in what role
  my $outer_aliastypes =
    $self->_resolve_aliastypes_from_select_args( $from, $outer_select, $where, $outer_attrs );

  # unroll parents
  my ($outer_select_chain, @outer_nonselecting_chains) = map { +{
    map { $_ => 1 } map { values %$_} map { @{$_->{-parents}} } values %{ $outer_aliastypes->{$_} || {} }
  } } qw/selecting restricting grouping ordering/;

  # see what's left - throw away if not selecting/restricting
  # also throw in a group_by if a non-selecting multiplier,
  # to guard against cross-join explosions
  my $need_outer_group_by;
  while (my $j = shift @$from) {
    my $alias = $j->[0]{-alias};

    if (
      $outer_select_chain->{$alias}
    ) {
      push @outer_from, $j
    }
    elsif (first { $_->{$alias} } @outer_nonselecting_chains ) {
      push @outer_from, $j;
      $need_outer_group_by ||= $outer_aliastypes->{multiplying}{$alias} ? 1 : 0;
    }
  }

  if ( $need_outer_group_by and $attrs->{_grouped_by_distinct} ) {
    my $unprocessed_order_chunks;
    ($outer_attrs->{group_by}, $unprocessed_order_chunks) = $self->_group_over_selection (
      \@outer_from, $outer_select, $outer_attrs->{order_by}
    );

    $self->throw_exception (
      'A required group_by clause could not be constructed automatically due to a complex '
    . 'order_by criteria. Either order_by columns only (no functions) or construct a suitable '
    . 'group_by by hand'
    ) if $unprocessed_order_chunks;

  }

  # This is totally horrific - the $where ends up in both the inner and outer query
  # Unfortunately not much can be done until SQLA2 introspection arrives, and even
  # then if where conditions apply to the *right* side of the prefetch, you may have
  # to both filter the inner select (e.g. to apply a limit) and then have to re-filter
  # the outer select to exclude joins you didin't want in the first place
  #
  # OTOH it can be seen as a plus: <ash> (notes that this query would make a DBA cry ;)
  return (\@outer_from, $outer_select, $where, $outer_attrs);
}

#
# I KNOW THIS SUCKS! GET SQLA2 OUT THE DOOR SO THIS CAN DIE!
#
# Due to a lack of SQLA2 we fall back to crude scans of all the
# select/where/order/group attributes, in order to determine what
# aliases are neded to fulfill the query. This information is used
# throughout the code to prune unnecessary JOINs from the queries
# in an attempt to reduce the execution time.
# Although the method is pretty horrific, the worst thing that can
# happen is for it to fail due to some scalar SQL, which in turn will
# result in a vocal exception.
sub _resolve_aliastypes_from_select_args {
  my ( $self, $from, $select, $where, $attrs ) = @_;

  $self->throw_exception ('Unable to analyze custom {from}')
    if ref $from ne 'ARRAY';

  # what we will return
  my $aliases_by_type;

  # see what aliases are there to work with
  my $alias_list;
  for (@$from) {
    my $j = $_;
    $j = $j->[0] if ref $j eq 'ARRAY';
    my $al = $j->{-alias}
      or next;

    $alias_list->{$al} = $j;
    $aliases_by_type->{multiplying}{$al} ||= { -parents => $j->{-join_path}||[] } if (
      # not array == {from} head == can't be multiplying
      ( ref($_) eq 'ARRAY' and ! $j->{-is_single} )
        or
      # a parent of ours is already a multiplier
      ( grep { $aliases_by_type->{multiplying}{$_} } @{ $j->{-join_path}||[] } )
    );
  }

  # get a column to source/alias map (including unambiguous unqualified ones)
  my $colinfo = $self->_resolve_column_info ($from);

  # set up a botched SQLA
  my $sql_maker = $self->sql_maker;

  # these are throw away results, do not pollute the bind stack
  local $sql_maker->{select_bind};
  local $sql_maker->{where_bind};
  local $sql_maker->{group_bind};
  local $sql_maker->{having_bind};
  local $sql_maker->{from_bind};

  # we can't scan properly without any quoting (\b doesn't cut it
  # everywhere), so unless there is proper quoting set - use our
  # own weird impossible character.
  # Also in the case of no quoting, we need to explicitly disable
  # name_sep, otherwise sorry nasty legacy syntax like
  # { 'count(foo.id)' => { '>' => 3 } } will stop working >:(
  local $sql_maker->{quote_char} = $sql_maker->{quote_char};
  local $sql_maker->{name_sep} = $sql_maker->{name_sep};

  unless (defined $sql_maker->{quote_char} and length $sql_maker->{quote_char}) {
    $sql_maker->{quote_char} = ["\x00", "\xFF"];
    # if we don't unset it we screw up retarded but unfortunately working
    # 'MAX(foo.bar)' => { '>', 3 }
    $sql_maker->{name_sep} = '';
  }

  my ($lquote, $rquote, $sep) = map { quotemeta $_ } ($sql_maker->_quote_chars, $sql_maker->name_sep);

  # generate sql chunks
  my $to_scan = {
    restricting => [
      $sql_maker->_recurse_where ($where),
      $sql_maker->_parse_rs_attrs ({ having => $attrs->{having} }),
    ],
    grouping => [
      $sql_maker->_parse_rs_attrs ({ group_by => $attrs->{group_by} }),
    ],
    joining => [
      $sql_maker->_recurse_from (
        ref $from->[0] eq 'ARRAY' ? $from->[0][0] : $from->[0],
        @{$from}[1 .. $#$from],
      ),
    ],
    selecting => [
      $sql_maker->_recurse_fields ($select),
    ],
    ordering => [
      map { $_->[0] } $self->_extract_order_criteria ($attrs->{order_by}, $sql_maker),
    ],
  };

  # throw away empty chunks
  $_ = [ map { $_ || () } @$_ ] for values %$to_scan;

  # first see if we have any exact matches (qualified or unqualified)
  for my $type (keys %$to_scan) {
    for my $piece (@{$to_scan->{$type}}) {
      if ($colinfo->{$piece} and my $alias = $colinfo->{$piece}{-source_alias}) {
        $aliases_by_type->{$type}{$alias} ||= { -parents => $alias_list->{$alias}{-join_path}||[] };
        $aliases_by_type->{$type}{$alias}{-seen_columns}{$colinfo->{$piece}{-fq_colname}} = $piece;
      }
    }
  }

  # now loop through all fully qualified columns and get the corresponding
  # alias (should work even if they are in scalarrefs)
  for my $alias (keys %$alias_list) {
    my $al_re = qr/
      $lquote $alias $rquote $sep (?: $lquote ([^$rquote]+) $rquote )?
        |
      \b $alias \. ([^\s\)\($rquote]+)?
    /x;

    for my $type (keys %$to_scan) {
      for my $piece (@{$to_scan->{$type}}) {
        if (my @matches = $piece =~ /$al_re/g) {
          $aliases_by_type->{$type}{$alias} ||= { -parents => $alias_list->{$alias}{-join_path}||[] };
          $aliases_by_type->{$type}{$alias}{-seen_columns}{"$alias.$_"} = "$alias.$_"
            for grep { defined $_ } @matches;
        }
      }
    }
  }

  # now loop through unqualified column names, and try to locate them within
  # the chunks
  for my $col (keys %$colinfo) {
    next if $col =~ / \. /x;   # if column is qualified it was caught by the above

    my $col_re = qr/ $lquote ($col) $rquote /x;

    for my $type (keys %$to_scan) {
      for my $piece (@{$to_scan->{$type}}) {
        if ( my @matches = $piece =~ /$col_re/g) {
          my $alias = $colinfo->{$col}{-source_alias};
          $aliases_by_type->{$type}{$alias} ||= { -parents => $alias_list->{$alias}{-join_path}||[] };
          $aliases_by_type->{$type}{$alias}{-seen_columns}{"$alias.$_"} = $_
            for grep { defined $_ } @matches;
        }
      }
    }
  }

  # Add any non-left joins to the restriction list (such joins are indeed restrictions)
  for my $j (values %$alias_list) {
    my $alias = $j->{-alias} or next;
    $aliases_by_type->{restricting}{$alias} ||= { -parents => $j->{-join_path}||[] } if (
      (not $j->{-join_type})
        or
      ($j->{-join_type} !~ /^left (?: \s+ outer)? $/xi)
    );
  }

  for (keys %$aliases_by_type) {
    delete $aliases_by_type->{$_} unless keys %{$aliases_by_type->{$_}};
  }

  return $aliases_by_type;
}

# This is the engine behind { distinct => 1 }
sub _group_over_selection {
  my ($self, $from, $select, $order_by) = @_;

  my $rs_column_list = $self->_resolve_column_info ($from);

  my (@group_by, %group_index);

  # the logic is: if it is a { func => val } we assume an aggregate,
  # otherwise if \'...' or \[...] we assume the user knows what is
  # going on thus group over it
  for (@$select) {
    if (! ref($_) or ref ($_) ne 'HASH' ) {
      push @group_by, $_;
      $group_index{$_}++;
      if ($rs_column_list->{$_} and $_ !~ /\./ ) {
        # add a fully qualified version as well
        $group_index{"$rs_column_list->{$_}{-source_alias}.$_"}++;
      }
    }
  }

  # add any order_by parts that are not already present in the group_by
  # we need to be careful not to add any named functions/aggregates
  # i.e. order_by => [ ... { count => 'foo' } ... ]
  my @leftovers;
  for ($self->_extract_order_criteria($order_by)) {
    # only consider real columns (for functions the user got to do an explicit group_by)
    if (@$_ != 1) {
      push @leftovers, $_;
      next;
    }
    my $chunk = $_->[0];
    my $colinfo = $rs_column_list->{$chunk} or do {
      push @leftovers, $_;
      next;
    };

    $chunk = "$colinfo->{-source_alias}.$chunk" if $chunk !~ /\./;
    push @group_by, $chunk unless $group_index{$chunk}++;
  }

  return wantarray
    ? (\@group_by, (@leftovers ? \@leftovers : undef) )
    : \@group_by
  ;
}

sub _resolve_ident_sources {
  my ($self, $ident) = @_;

  my $alias2source = {};

  # the reason this is so contrived is that $ident may be a {from}
  # structure, specifying multiple tables to join
  if ( blessed $ident && $ident->isa("DBIx::Class::ResultSource") ) {
    # this is compat mode for insert/update/delete which do not deal with aliases
    $alias2source->{me} = $ident;
  }
  elsif (ref $ident eq 'ARRAY') {

    for (@$ident) {
      my $tabinfo;
      if (ref $_ eq 'HASH') {
        $tabinfo = $_;
      }
      if (ref $_ eq 'ARRAY' and ref $_->[0] eq 'HASH') {
        $tabinfo = $_->[0];
      }

      $alias2source->{$tabinfo->{-alias}} = $tabinfo->{-rsrc}
        if ($tabinfo->{-rsrc});
    }
  }

  return $alias2source;
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
  my $alias2src = $self->_resolve_ident_sources($ident);

  my (%seen_cols, @auto_colnames);

  # compile a global list of column names, to be able to properly
  # disambiguate unqualified column names (if at all possible)
  for my $alias (keys %$alias2src) {
    my $rsrc = $alias2src->{$alias};
    for my $colname ($rsrc->columns) {
      push @{$seen_cols{$colname}}, $alias;
      push @auto_colnames, "$alias.$colname" unless $colnames;
    }
  }

  $colnames ||= [
    @auto_colnames,
    grep { @{$seen_cols{$_}} == 1 } (keys %seen_cols),
  ];

  my (%return, $colinfos);
  foreach my $col (@$colnames) {
    my ($source_alias, $colname) = $col =~ m/^ (?: ([^\.]+) \. )? (.+) $/x;

    # if the column was seen exactly once - we know which rsrc it came from
    $source_alias ||= $seen_cols{$colname}[0]
      if ($seen_cols{$colname} and @{$seen_cols{$colname}} == 1);

    next unless $source_alias;

    my $rsrc = $alias2src->{$source_alias}
      or next;

    $return{$col} = {
      %{
          ( $colinfos->{$source_alias} ||= $rsrc->columns_info )->{$colname}
            ||
          $self->throw_exception(
            "No such column '$colname' on source " . $rsrc->source_name
          );
      },
      -result_source => $rsrc,
      -source_alias => $source_alias,
      -fq_colname => $col eq $colname ? "$source_alias.$col" : $col,
      -colname => $colname,
    };

    $return{"$source_alias.$colname"} = $return{$col} if $col eq $colname;
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
sub _inner_join_to_node {
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
  my $sw_idx = { map { (values %$_), 1 } @$switch_branch }; #there's one k/v per join-path

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

sub _extract_order_criteria {
  my ($self, $order_by, $sql_maker) = @_;

  my $parser = sub {
    my ($sql_maker, $order_by, $orig_quote_chars) = @_;

    return scalar $sql_maker->_order_by_chunks ($order_by)
      unless wantarray;

    my ($lq, $rq, $sep) = map { quotemeta($_) } (
      ($orig_quote_chars ? @$orig_quote_chars : $sql_maker->_quote_chars),
      $sql_maker->name_sep
    );

    my @chunks;
    for ($sql_maker->_order_by_chunks ($order_by) ) {
      my $chunk = ref $_ ? [ @$_ ] : [ $_ ];
      ($chunk->[0]) = $sql_maker->_split_order_chunk($chunk->[0]);

      # order criteria may have come back pre-quoted (literals and whatnot)
      # this is fragile, but the best we can currently do
      $chunk->[0] =~ s/^ $lq (.+?) $rq $sep $lq (.+?) $rq $/"$1.$2"/xe
        or $chunk->[0] =~ s/^ $lq (.+) $rq $/$1/x;

      push @chunks, $chunk;
    }

    return @chunks;
  };

  if ($sql_maker) {
    return $parser->($sql_maker, $order_by);
  }
  else {
    $sql_maker = $self->sql_maker;

    # pass these in to deal with literals coming from
    # the user or the deep guts of prefetch
    my $orig_quote_chars = [$sql_maker->_quote_chars];

    local $sql_maker->{quote_char};
    return $parser->($sql_maker, $order_by, $orig_quote_chars);
  }
}

sub _order_by_is_stable {
  my ($self, $ident, $order_by, $where) = @_;

  my $colinfo = $self->_resolve_column_info($ident, [
    (map { $_->[0] } $self->_extract_order_criteria($order_by)),
    $where ? @{$self->_extract_fixed_condition_columns($where)} :(),
  ]);

  return undef unless keys %$colinfo;

  my $cols_per_src;
  $cols_per_src->{$_->{-source_alias}}{$_->{-colname}} = $_ for values %$colinfo;

  for (values %$cols_per_src) {
    my $src = (values %$_)[0]->{-result_source};
    return 1 if $src->_identifying_column_set($_);
  }

  return undef;
}

# this is almost identical to the above, except it accepts only
# a single rsrc, and will succeed only if the first portion of the order
# by is stable.
# returns that portion as a colinfo hashref on success
sub _main_source_order_by_portion_is_stable {
  my ($self, $main_rsrc, $order_by, $where) = @_;

  die "Huh... I expect a blessed result_source..."
    if ref($main_rsrc) eq 'ARRAY';

  my @ord_cols = map
    { $_->[0] }
    ( $self->_extract_order_criteria($order_by) )
  ;
  return unless @ord_cols;

  my $colinfos = $self->_resolve_column_info($main_rsrc);

  for (0 .. $#ord_cols) {
    if (
      ! $colinfos->{$ord_cols[$_]}
        or
      $colinfos->{$ord_cols[$_]}{-result_source} != $main_rsrc
    ) {
      $#ord_cols =  $_ - 1;
      last;
    }
  }

  # we just truncated it above
  return unless @ord_cols;

  my $order_portion_ci = { map {
    $colinfos->{$_}{-colname} => $colinfos->{$_},
    $colinfos->{$_}{-fq_colname} => $colinfos->{$_},
  } @ord_cols };

  # since all we check here are the start of the order_by belonging to the
  # top level $rsrc, a present identifying set will mean that the resultset
  # is ordered by its leftmost table in a stable manner
  #
  # RV of _identifying_column_set contains unqualified names only
  my $unqualified_idset = $main_rsrc->_identifying_column_set({
    ( $where ? %{
      $self->_resolve_column_info(
        $main_rsrc, $self->_extract_fixed_condition_columns($where)
      )
    } : () ),
    %$order_portion_ci
  }) or return;

  my $ret_info;
  my %unqualified_idcols_from_order = map {
    $order_portion_ci->{$_} ? ( $_ => $order_portion_ci->{$_} ) : ()
  } @$unqualified_idset;

  # extra optimization - cut the order_by at the end of the identifying set
  # (just in case the user was stupid and overlooked the obvious)
  for my $i (0 .. $#ord_cols) {
    my $col = $ord_cols[$i];
    my $unqualified_colname = $order_portion_ci->{$col}{-colname};
    $ret_info->{$col} = { %{$order_portion_ci->{$col}}, -idx_in_order_subset => $i };
    delete $unqualified_idcols_from_order{$ret_info->{$col}{-colname}};

    # we didn't reach the end of the identifying portion yet
    return $ret_info unless keys %unqualified_idcols_from_order;
  }

  die 'How did we get here...';
}

# returns an arrayref of column names which *definitely* have som
# sort of non-nullable equality requested in the given condition
# specification. This is used to figure out if a resultset is
# constrained to a column which is part of a unique constraint,
# which in turn allows us to better predict how ordering will behave
# etc.
#
# this is a rudimentary, incomplete, and error-prone extractor
# however this is OK - it is conservative, and if we can not find
# something that is in fact there - the stack will recover gracefully
# Also - DQ and the mst it rode in on will save us all RSN!!!
sub _extract_fixed_condition_columns {
  my ($self, $where, $nested) = @_;

  return unless ref $where eq 'HASH';

  my @cols;
  for my $lhs (keys %$where) {
    if ($lhs =~ /^\-and$/i) {
      push @cols, ref $where->{$lhs} eq 'ARRAY'
        ? ( map { $self->_extract_fixed_condition_columns($_, 1) } @{$where->{$lhs}} )
        : $self->_extract_fixed_condition_columns($where->{$lhs}, 1)
      ;
    }
    elsif ($lhs !~ /^\-/) {
      my $val = $where->{$lhs};

      push @cols, $lhs if (defined $val and (
        ! ref $val
          or
        (ref $val eq 'HASH' and keys %$val == 1 and defined $val->{'='})
      ));
    }
  }
  return $nested ? @cols : \@cols;
}

1;

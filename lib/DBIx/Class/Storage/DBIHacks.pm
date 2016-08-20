package   #hide from PAUSE
  DBIx::Class::Storage::DBIHacks;

#
# This module contains code supporting a battery of special cases and tests for
# many corner cases pushing the envelope of what DBIC can do. When work on
# these utilities began in mid 2009 (51a296b402c) it wasn't immediately obvious
# that these pieces, despite their misleading on-first-sight-flakiness, will
# become part of the generic query rewriting machinery of DBIC, allowing it to
# both generate and process queries representing incredibly complex sets with
# reasonable efficiency.
#
# Now (end of 2015), more than 6 years later the routines in this class have
# stabilized enough, and are meticulously covered with tests, to a point where
# an effort to formalize them into user-facing APIs might be worthwhile.
#
# An implementor working on publicizing and/or replacing the routines with a
# more modern SQL generation framework should keep in mind that pretty much all
# existing tests are constructed on the basis of real-world code used in
# production somewhere.
#
# Please hack on this responsibly ;)
#

use strict;
use warnings;

use base 'DBIx::Class::Storage';
use mro 'c3';

use Scalar::Util 'blessed';
use DBIx::Class::_Util qw(
  dump_value fail_on_internal_call
);
use DBIx::Class::SQLMaker::Util 'extract_equality_conditions';
use DBIx::Class::ResultSource::FromSpec::Util qw(
  fromspec_columns_info
  find_join_path_to_alias
);
use DBIx::Class::Carp;
use namespace::clean;

#
# This code will remove non-selecting/non-restricting joins from
# {from} specs, aiding the RDBMS query optimizer
#
sub _prune_unused_joins {
  my ($self, $attrs) = @_;

  # only standard {from} specs are supported, and we could be disabled in general
  return ($attrs->{from}, {})  unless (
    ref $attrs->{from} eq 'ARRAY'
      and
    @{$attrs->{from}} > 1
      and
    ref $attrs->{from}[0] eq 'HASH'
      and
    ref $attrs->{from}[1] eq 'ARRAY'
      and
    $self->_use_join_optimizer
  );

  my $orig_aliastypes =
    $attrs->{_precalculated_aliastypes}
      ||
    $self->_resolve_aliastypes_from_select_args($attrs)
  ;

  my $new_aliastypes = { %$orig_aliastypes };

  # we will be recreating this entirely
  my @reclassify = 'joining';

  # a grouped set will not be affected by amount of rows. Thus any
  # purely multiplicator classifications can go
  # (will be reintroduced below if needed by something else)
  push @reclassify, qw(multiplying premultiplied)
    if $attrs->{_force_prune_multiplying_joins} or $attrs->{group_by};

  # nuke what will be recalculated
  delete @{$new_aliastypes}{@reclassify};

  my @newfrom = $attrs->{from}[0]; # FROM head is always present

  # recalculate what we need once the multipliers are potentially gone
  # ignore premultiplies, since they do not add any value to anything
  my %need_joins;
  for ( @{$new_aliastypes}{grep { $_ ne 'premultiplied' } keys %$new_aliastypes }) {
    # add all requested aliases
    $need_joins{$_} = 1 for keys %$_;

    # add all their parents (as per joinpath which is an AoH { table => alias })
    $need_joins{$_} = 1 for map { values %$_ } map { @{$_->{-parents}} } values %$_;
  }

  for my $j (@{$attrs->{from}}[1..$#{$attrs->{from}}]) {
    push @newfrom, $j if (
      (! defined $j->[0]{-alias}) # legacy crap
        ||
      $need_joins{$j->[0]{-alias}}
    );
  }

  # we have a new set of joiners - for everything we nuked pull the classification
  # off the original stack
  for my $ctype (@reclassify) {
    $new_aliastypes->{$ctype} = { map
      { $need_joins{$_} ? ( $_ => $orig_aliastypes->{$ctype}{$_} ) : () }
      keys %{$orig_aliastypes->{$ctype}}
    }
  }

  return ( \@newfrom, $new_aliastypes );
}

#
# This is the code producing joined subqueries like:
# SELECT me.*, other.* FROM ( SELECT me.* FROM ... ) JOIN other ON ...
#
sub _adjust_select_args_for_complex_prefetch {
  my ($self, $attrs) = @_;

  $self->throw_exception ('Complex prefetches are not supported on resultsets with a custom from attribute') unless (
    ref $attrs->{from} eq 'ARRAY'
      and
    @{$attrs->{from}} > 1
      and
    ref $attrs->{from}[0] eq 'HASH'
      and
    ref $attrs->{from}[1] eq 'ARRAY'
  );

  my $root_alias = $attrs->{alias};

  # generate inner/outer attribute lists, remove stuff that doesn't apply
  my $outer_attrs = { %$attrs };
  delete @{$outer_attrs}{qw(from bind rows offset group_by _grouped_by_distinct having)};

  my $inner_attrs = { %$attrs, _simple_passthrough_construction => 1 };
  delete @{$inner_attrs}{qw(for collapse select as)};

  # there is no point of ordering the insides if there is no limit
  delete $inner_attrs->{order_by} if (
    delete $inner_attrs->{_order_is_artificial}
      or
    ! $inner_attrs->{rows}
  );

  # generate the inner/outer select lists
  # for inside we consider only stuff *not* brought in by the prefetch
  # on the outside we substitute any function for its alias
  $outer_attrs->{select} = [ @{$attrs->{select}} ];

  my ($root_node, $root_node_offset);

  for my $i (0 .. $#{$inner_attrs->{from}}) {
    my $node = $inner_attrs->{from}[$i];
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
  my $colinfo = fromspec_columns_info($inner_attrs->{from});
  my $selected_root_columns;

  for my $i (0 .. $#{$outer_attrs->{select}}) {
    my $sel = $outer_attrs->{select}->[$i];

    next if (
      $colinfo->{$sel} and $colinfo->{$sel}{-source_alias} ne $root_alias
    );

    if (ref $sel eq 'HASH' ) {
      $sel->{-as} ||= $attrs->{as}[$i];
      $outer_attrs->{select}->[$i] = join ('.', $root_alias, ($sel->{-as} || "inner_column_$i") );
    }
    elsif (! ref $sel and my $ci = $colinfo->{$sel}) {
      $selected_root_columns->{$ci->{-colname}} = 1;
    }

    push @{$inner_attrs->{select}}, $sel;

    push @{$inner_attrs->{as}}, $attrs->{as}[$i];
  }

  my $inner_aliastypes = $self->_resolve_aliastypes_from_select_args($inner_attrs);

  # In the inner subq we will need to fetch *only* native columns which may
  # be a part of an *outer* join condition, or an order_by (which needs to be
  # preserved outside), or wheres. In other words everything but the inner
  # selector
  # We can not just fetch everything because a potential has_many restricting
  # join collapse *will not work* on heavy data types.

  # essentially a map of all non-selecting seen columns
  # the sort is there for a nicer select list
  for (
    sort
      map
        { keys %{$_->{-seen_columns}||{}} }
        map
          { values %{$inner_aliastypes->{$_}} }
          grep
            { $_ ne 'selecting' }
            keys %$inner_aliastypes
  ) {
    my $ci = $colinfo->{$_} or next;
    if (
      $ci->{-source_alias} eq $root_alias
        and
      ! $selected_root_columns->{$ci->{-colname}}++
    ) {
      # adding it to both to keep limits not supporting dark selectors happy
      push @{$inner_attrs->{select}}, $ci->{-fq_colname};
      push @{$inner_attrs->{as}}, $ci->{-fq_colname};
    }
  }

  # construct the inner {from} and lock it in a subquery
  # we need to prune first, because this will determine if we need a group_by below
  # throw away all non-selecting, non-restricting multijoins
  # (since we def. do not care about multiplication of the contents of the subquery)
  my $inner_subq = do {

    # must use it here regardless of user requests (vastly gentler on optimizer)
    local $self->{_use_join_optimizer} = 1
      unless $self->{_use_join_optimizer};

    # throw away multijoins since we def. do not care about those inside the subquery
    # $inner_aliastypes *will* be redefined at this point
    ($inner_attrs->{from}, $inner_aliastypes ) = $self->_prune_unused_joins ({
      %$inner_attrs,
      _force_prune_multiplying_joins => 1,
      _precalculated_aliastypes => $inner_aliastypes,
    });

    # uh-oh a multiplier (which is not us) left in, this is a problem for limits
    # we will need to add a group_by to collapse the resultset for proper counts
    if (
      grep { $_ ne $root_alias } keys %{ $inner_aliastypes->{multiplying} || {} }
        and
      # if there are user-supplied groups - assume user knows wtf they are up to
      ( ! $inner_aliastypes->{grouping} or $inner_attrs->{_grouped_by_distinct} )
    ) {

      my $cur_sel = { map { $_ => 1 } @{$inner_attrs->{select}} };

      # *possibly* supplement the main selection with pks if not already
      # there, as they will have to be a part of the group_by to collapse
      # things properly
      my $inner_select_with_extras;
      my @pks = map { "$root_alias.$_" } $root_node->{-rsrc}->primary_columns
        or $self->throw_exception( sprintf
          'Unable to perform complex limited prefetch off %s without declared primary key',
          $root_node->{-rsrc}->source_name,
        );
      for my $col (@pks) {
        push @{ $inner_select_with_extras ||= [ @{$inner_attrs->{select}} ] }, $col
          unless $cur_sel->{$col}++;
      }

      ($inner_attrs->{group_by}, $inner_attrs->{order_by}) = $self->_group_over_selection({
        %$inner_attrs,
        $inner_select_with_extras ? ( select => $inner_select_with_extras ) : (),
        _aliastypes => $inner_aliastypes,
      });
    }

    # we already optimized $inner_attrs->{from} above
    # and already local()ized
    $self->{_use_join_optimizer} = 0;

    # generate the subquery
    $self->_select_args_to_query (
      @{$inner_attrs}{qw(from select where)},
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
  my @orig_from = @{$attrs->{from}};


  $outer_attrs->{from} = \ my @outer_from;

  # we may not be the head
  if ($root_node_offset) {
    # first generate the outer_from, up to the substitution point
    @outer_from = splice @orig_from, 0, $root_node_offset;

    # substitute the subq at the right spot
    push @outer_from, [
      {
        -alias => $root_alias,
        -rsrc => $root_node->{-rsrc},
        $root_alias => $inner_subq,
      },
      # preserve attrs from what is now the head of the from after the splice
      @{$orig_from[0]}[1 .. $#{$orig_from[0]}],
    ];
  }
  else {
    @outer_from = {
      -alias => $root_alias,
      -rsrc => $root_node->{-rsrc},
      $root_alias => $inner_subq,
    };
  }

  shift @orig_from; # what we just replaced above

  # scan the *remaining* from spec against different attributes, and see which joins are needed
  # in what role
  my $outer_aliastypes = $outer_attrs->{_aliastypes} =
    $self->_resolve_aliastypes_from_select_args({ %$outer_attrs, from => \@orig_from });

  # unroll parents
  my ($outer_select_chain, @outer_nonselecting_chains) = map { +{
    map { $_ => 1 } map { values %$_} map { @{$_->{-parents}} } values %{ $outer_aliastypes->{$_} || {} }
  } } qw/selecting restricting grouping ordering/;

  # see what's left - throw away if not selecting/restricting
  my $may_need_outer_group_by;
  while (my $j = shift @orig_from) {
    my $alias = $j->[0]{-alias};

    if (
      $outer_select_chain->{$alias}
    ) {
      push @outer_from, $j
    }
    elsif (grep { $_->{$alias} } @outer_nonselecting_chains ) {
      push @outer_from, $j;
      $may_need_outer_group_by ||= $outer_aliastypes->{multiplying}{$alias} ? 1 : 0;
    }
  }

  # also throw in a synthetic group_by if a non-selecting multiplier,
  # to guard against cross-join explosions
  # the logic is somewhat fragile, but relies on the idea that if a user supplied
  # a group by on their own - they know what they were doing
  if ( $may_need_outer_group_by and $attrs->{_grouped_by_distinct} ) {
    ($outer_attrs->{group_by}, $outer_attrs->{order_by}) = $self->_group_over_selection ({
      %$outer_attrs,
      from => \@outer_from,
    });
  }

  # FIXME: The {where} ends up in both the inner and outer query, i.e. *twice*
  #
  # This is rather horrific, and while we currently *do* have enough
  # introspection tooling available to attempt a stab at properly deciding
  # whether or not to include the where condition on the outside, the
  # machinery is still too slow to apply it here.
  # Thus for the time being we do not attempt any sanitation of the where
  # clause and just pass it through on both sides of the subquery. This *will*
  # be addressed at a later stage, most likely after folding the SQL generator
  # into SQLMaker proper
  #
  # OTOH it can be seen as a plus: <ash> (notes that this query would make a DBA cry ;)
  #
  return $outer_attrs;
}

# This is probably the ickiest, yet most relied upon part of the codebase:
# this is the place where we take arbitrary SQL input and break it into its
# constituent parts, making sure we know which *sources* are used in what
# *capacity* ( selecting / restricting / grouping / ordering / joining, etc )
# Although the method is pretty horrific, the worst thing that can happen is
# for a classification failure, which in turn will result in a vocal exception,
# and will lead to a relatively prompt fix.
# The code has been slowly improving and is covered with a formiddable battery
# of tests, so can be considered "reliably stable" at this point (Oct 2015).
#
# A note to implementors attempting to "replace" this - keep in mind that while
# there are multiple optimization avenues, the actual "scan literal elements"
# part *MAY NEVER BE REMOVED*, even if it is limited only ot the (future) AST
# nodes that are deemed opaque (i.e. contain literal expressions). The use of
# blackbox literals is at this point firmly a user-facing API, and is one of
# *the* reasons DBIC remains as flexible as it is. In other words, when working
# on this keep in mind that the following is widespread and *encouraged* way
# of using DBIC in the wild when push comes to shove:
#
# $rs->search( {}, {
#   select => \[ $random, @stuff],
#   from => \[ $random, @stuff ],
#   where => \[ $random, @stuff ],
#   group_by => \[ $random, @stuff ],
#   order_by => \[ $random, @stuff ],
# } )
#
# Various incarnations of the above are reflected in many of the tests. If one
# gets to fail, you get to fix it. A "this is crazy, nobody does that" is not
# acceptable going forward.
#
sub _resolve_aliastypes_from_select_args {
  my ( $self, $attrs ) = @_;

  $self->throw_exception ('Unable to analyze custom {from}')
    if ref $attrs->{from} ne 'ARRAY';

  # what we will return
  my $aliases_by_type;

  # see what aliases are there to work with
  # and record who is a multiplier and who is premultiplied
  my $alias_list;
  for my $node (@{$attrs->{from}}) {

    my $j = $node;
    $j = $j->[0] if ref $j eq 'ARRAY';
    my $al = $j->{-alias}
      or next;

    $alias_list->{$al} = $j;

    $aliases_by_type->{multiplying}{$al} ||= { -parents => $j->{-join_path}||[] }
      # not array == {from} head == can't be multiplying
      if ref($node) eq 'ARRAY' and ! $j->{-is_single};

    $aliases_by_type->{premultiplied}{$al} ||= { -parents => $j->{-join_path}||[] }
      # parts of the path that are not us but are multiplying
      if grep { $aliases_by_type->{multiplying}{$_} }
          grep { $_ ne $al }
           map { values %$_ }
            @{ $j->{-join_path}||[] }
  }

  # get a column to source/alias map (including unambiguous unqualified ones)
  my $colinfo = fromspec_columns_info($attrs->{from});

  # set up a botched SQLA
  my $sql_maker = $self->sql_maker;

  # these are throw away results, do not pollute the bind stack
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
      ($sql_maker->_recurse_where ($attrs->{where}))[0],
      $sql_maker->_parse_rs_attrs ({ having => $attrs->{having} }),
    ],
    grouping => [
      $sql_maker->_parse_rs_attrs ({ group_by => $attrs->{group_by} }),
    ],
    joining => [
      $sql_maker->_recurse_from (
        ref $attrs->{from}[0] eq 'ARRAY' ? $attrs->{from}[0][0] : $attrs->{from}[0],
        @{$attrs->{from}}[1 .. $#{$attrs->{from}}],
      ),
    ],
    selecting => [
      # kill all selectors which look like a proper subquery
      # this is a sucky heuristic *BUT* - if we get it wrong the query will simply
      # fail to run, so we are relatively safe
      grep
        { $_ !~ / \A \s* \( \s* SELECT \s+ .+? \s+ FROM \s+ .+? \) \s* \z /xsi }
        map
          { ($sql_maker->_recurse_fields($_))[0] }
          @{$attrs->{select}}
    ],
    ordering => [ map
      {
        ( my $sql = (ref $_ ? $_->[0] : $_) ) =~ s/ \s+ (?: ASC | DESC ) \s* \z //xi;
        $sql;
      }
      $sql_maker->_order_by_chunks( $attrs->{order_by} ),
    ],
  };

  # we will be bulk-scanning anyway - pieces will not matter in that case,
  # thus join everything up
  # throw away empty-string chunks, and make sure no binds snuck in
  # note that we operate over @{$to_scan->{$type}}, hence the
  # semi-mindbending ... map ... for values ...
  ( $_ = join ' ', map {

    ( ! defined $_ )  ? ()
  : ( length ref $_ ) ? $self->throw_exception(
                          "Unexpected ref in scan-plan: " . dump_value $_
                        )
  : ( $_ =~ /^\s*$/ ) ? ()
                      : $_

  } @$_ ) for values %$to_scan;

  # throw away empty to-scan's
  (
    length $to_scan->{$_}
      or
    delete $to_scan->{$_}
  ) for keys %$to_scan;



  # these will be used for matching in the loop below
  my $all_aliases = join ' | ', map { quotemeta $_ } keys %$alias_list;
  my $fq_col_re = qr/
    $lquote ( $all_aliases ) $rquote $sep (?: $lquote ([^$rquote]+) $rquote )?
         |
    \b ( $all_aliases ) \. ( [^\s\)\($rquote]+ )?
  /x;


  my $all_unq_columns = join ' | ',
    map
      { quotemeta $_ }
      grep
        # using a regex here shows up on profiles, boggle
        { index( $_, '.') < 0 }
        keys %$colinfo
  ;
  my $unq_col_re = $all_unq_columns
    ? qr/
      $lquote ( $all_unq_columns ) $rquote
        |
      (?: \A | \s ) ( $all_unq_columns ) (?: \s | \z )
    /x
    : undef
  ;


  # the actual scan, per type
  for my $type (keys %$to_scan) {


    # now loop through all fully qualified columns and get the corresponding
    # alias (should work even if they are in scalarrefs)
    #
    # The regex captures in multiples of 4, with one of the two pairs being
    # undef. There may be a *lot* of matches, hence the convoluted loop
    my @matches = $to_scan->{$type} =~ /$fq_col_re/g;
    my $i = 0;
    while( $i < $#matches ) {

      if (
        defined $matches[$i]
      ) {
        $aliases_by_type->{$type}{$matches[$i]} ||= { -parents => $alias_list->{$matches[$i]}{-join_path}||[] };

        $aliases_by_type->{$type}{$matches[$i]}{-seen_columns}{"$matches[$i].$matches[$i+1]"} = "$matches[$i].$matches[$i+1]"
          if defined $matches[$i+1];

        $i += 2;
      }

      $i += 2;
    }


    # now loop through unqualified column names, and try to locate them within
    # the chunks, if there are any unqualified columns in the 1st place
    next unless $unq_col_re;

    # The regex captures in multiples of 2, one of the two being undef
    for ( $to_scan->{$type} =~ /$unq_col_re/g ) {
      defined $_ or next;
      my $alias = $colinfo->{$_}{-source_alias} or next;
      $aliases_by_type->{$type}{$alias} ||= { -parents => $alias_list->{$alias}{-join_path}||[] };
      $aliases_by_type->{$type}{$alias}{-seen_columns}{"$alias.$_"} = $_
    }
  }


  # Add any non-left joins to the restriction list (such joins are indeed restrictions)
  (
    $_->{-alias}
      and
    ! $aliases_by_type->{restricting}{ $_->{-alias} }
      and
    (
      not $_->{-join_type}
        or
      $_->{-join_type} !~ /^left (?: \s+ outer)? $/xi
    )
      and
    $aliases_by_type->{restricting}{ $_->{-alias} } = { -parents => $_->{-join_path}||[] }
  ) for values %$alias_list;


  # final cleanup
  (
    keys %{$aliases_by_type->{$_}}
      or
    delete $aliases_by_type->{$_}
  ) for keys %$aliases_by_type;


  $aliases_by_type;
}

# This is the engine behind { distinct => 1 } and the general
# complex prefetch grouper
sub _group_over_selection {
  my ($self, $attrs) = @_;

  my $colinfos = fromspec_columns_info($attrs->{from});

  my (@group_by, %group_index);

  # the logic is: if it is a { func => val } we assume an aggregate,
  # otherwise if \'...' or \[...] we assume the user knows what is
  # going on thus group over it
  for (@{$attrs->{select}}) {
    if (! ref($_) or ref ($_) ne 'HASH' ) {
      push @group_by, $_;
      $group_index{$_}++;
      if ($colinfos->{$_} and $_ !~ /\./ ) {
        # add a fully qualified version as well
        $group_index{"$colinfos->{$_}{-source_alias}.$_"}++;
      }
    }
  }

  my @order_by = $self->_extract_order_criteria($attrs->{order_by})
    or return (\@group_by, $attrs->{order_by});

  # add any order_by parts that are not already present in the group_by
  # to maintain SQL cross-compatibility and general sanity
  #
  # also in case the original selection is *not* unique, or in case part
  # of the ORDER BY refers to a multiplier - we will need to replace the
  # skipped order_by elements with their MIN/MAX equivalents as to maintain
  # the proper overall order without polluting the group criteria (and
  # possibly changing the outcome entirely)

  my ($leftovers, $sql_maker, @new_order_by, $order_chunks, $aliastypes);

  my $group_already_unique = $self->_columns_comprise_identifying_set($colinfos, \@group_by);

  for my $o_idx (0 .. $#order_by) {

    # if the chunk is already a min/max function - there is nothing left to touch
    next if $order_by[$o_idx][0] =~ /^ (?: min | max ) \s* \( .+ \) $/ix;

    # only consider real columns (for functions the user got to do an explicit group_by)
    my $chunk_ci;
    if (
      @{$order_by[$o_idx]} != 1
        or
      # only declare an unknown *plain* identifier as "leftover" if we are called with
      # aliastypes to examine. If there are none - we are still in _resolve_attrs, and
      # can just assume the user knows what they want
      ( ! ( $chunk_ci = $colinfos->{$order_by[$o_idx][0]} ) and $attrs->{_aliastypes} )
    ) {
      push @$leftovers, $order_by[$o_idx][0];
    }

    next unless $chunk_ci;

    # no duplication of group criteria
    next if $group_index{$chunk_ci->{-fq_colname}};

    $aliastypes ||= (
      $attrs->{_aliastypes}
        or
      $self->_resolve_aliastypes_from_select_args({
        from => $attrs->{from},
        order_by => $attrs->{order_by},
      })
    ) if $group_already_unique;

    # check that we are not ordering by a multiplier (if a check is requested at all)
    if (
      $group_already_unique
        and
      ! $aliastypes->{multiplying}{$chunk_ci->{-source_alias}}
        and
      ! $aliastypes->{premultiplied}{$chunk_ci->{-source_alias}}
    ) {
      push @group_by, $chunk_ci->{-fq_colname};
      $group_index{$chunk_ci->{-fq_colname}}++
    }
    else {
      # We need to order by external columns without adding them to the group
      # (eiehter a non-unique selection, or a multi-external)
      #
      # This doesn't really make sense in SQL, however from DBICs point
      # of view is rather valid (e.g. order the leftmost objects by whatever
      # criteria and get the offset/rows many). There is a way around
      # this however in SQL - we simply tae the direction of each piece
      # of the external order and convert them to MIN(X) for ASC or MAX(X)
      # for DESC, and group_by the root columns. The end result should be
      # exactly what we expect
      #

      # both populated on the first loop over $o_idx
      $sql_maker ||= $self->sql_maker;
      $order_chunks ||= [
        map { ref $_ eq 'ARRAY' ? $_ : [ $_ ] } $sql_maker->_order_by_chunks($attrs->{order_by})
      ];

      my ($chunk, $is_desc) = $sql_maker->_split_order_chunk($order_chunks->[$o_idx][0]);

      # we reached that far - wrap any part of the order_by that "responded"
      # to an ordering alias into a MIN/MAX
      $new_order_by[$o_idx] = \[
        sprintf( '%s( %s )%s',
          $self->_minmax_operator_for_datatype($chunk_ci->{data_type}, $is_desc),
          $chunk,
          ($is_desc ? ' DESC' : ''),
        ),
        @ {$order_chunks->[$o_idx]} [ 1 .. $#{$order_chunks->[$o_idx]} ]
      ];
    }
  }

  $self->throw_exception ( sprintf
    'Unable to programatically derive a required group_by from the supplied '
  . 'order_by criteria. To proceed either add an explicit group_by, or '
  . 'simplify your order_by to only include plain columns '
  . '(supplied order_by: %s)',
    join ', ', map { "'$_'" } @$leftovers,
  ) if $leftovers;

  # recreate the untouched order parts
  if (@new_order_by) {
    $new_order_by[$_] ||= \ $order_chunks->[$_] for ( 0 .. $#$order_chunks );
  }

  return (
    \@group_by,
    (@new_order_by ? \@new_order_by : $attrs->{order_by} ),  # same ref as original == unchanged
  );
}

sub _minmax_operator_for_datatype {
  #my ($self, $datatype, $want_max) = @_;

  $_[2] ? 'MAX' : 'MIN';
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

  my @cols = (
    ( map { $_->[0] } $self->_extract_order_criteria($order_by) ),
    ( $where ? keys %{ extract_equality_conditions( $where ) } : () ),
  ) or return 0;

  my $colinfo = fromspec_columns_info($ident, \@cols);

  return keys %$colinfo
    ? $self->_columns_comprise_identifying_set( $colinfo,  \@cols )
    : 0
  ;
}

sub _columns_comprise_identifying_set {
  my ($self, $colinfo, $columns) = @_;

  my $cols_per_src;
  $cols_per_src -> {$_->{-source_alias}} -> {$_->{-colname}} = $_
    for grep { defined $_ } @{$colinfo}{@$columns};

  for (values %$cols_per_src) {
    my $src = (values %$_)[0]->{-result_source};
    return 1 if $src->_identifying_column_set($_);
  }

  return 0;
}

# this is almost similar to _order_by_is_stable, except it takes
# a single rsrc, and will succeed only if the first portion of the order
# by is stable.
# returns that portion as a colinfo hashref on success
sub _extract_colinfo_of_stable_main_source_order_by_portion {
  my ($self, $attrs) = @_;

  my $nodes = find_join_path_to_alias($attrs->{from}, $attrs->{alias});

  return unless defined $nodes;

  my @ord_cols = map
    { $_->[0] }
    ( $self->_extract_order_criteria($attrs->{order_by}) )
  ;
  return unless @ord_cols;

  my $valid_aliases = { map { $_ => 1 } (
    $attrs->{from}[0]{-alias},
    map { values %$_ } @$nodes,
  ) };

  my $colinfos = fromspec_columns_info($attrs->{from});

  my ($colinfos_to_return, $seen_main_src_cols);

  for my $col (@ord_cols) {
    # if order criteria is unresolvable - there is nothing we can do
    my $colinfo = $colinfos->{$col} or last;

    # if we reached the end of the allowed aliases - also nothing we can do
    last unless $valid_aliases->{$colinfo->{-source_alias}};

    $colinfos_to_return->{$col} = $colinfo;

    $seen_main_src_cols->{$colinfo->{-colname}} = 1
      if $colinfo->{-source_alias} eq $attrs->{alias};
  }

  # FIXME: the condition may be singling out things on its own, so we
  # conceivably could come back with "stable-ordered by nothing"
  # not confident enough in the parser yet, so punt for the time being
  return unless $seen_main_src_cols;

  my $main_src_fixed_cols_from_cond = [ $attrs->{where}
    ? (
      map
      {
        ( $colinfos->{$_} and $colinfos->{$_}{-source_alias} eq $attrs->{alias} )
          ? $colinfos->{$_}{-colname}
          : ()
      }
      keys %{ extract_equality_conditions( $attrs->{where} ) }
    )
    : ()
  ];

  return $attrs->{result_source}->_identifying_column_set([
    keys %$seen_main_src_cols,
    @$main_src_fixed_cols_from_cond,
  ]) ? $colinfos_to_return : ();
}

sub _resolve_column_info :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  carp_unique("_resolve_column_info() is deprecated, ask on IRC for a better alternative");

  fromspec_columns_info( @_[1,2] );
}

sub _find_join_path_to_node :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  carp_unique("_find_join_path_to_node() is deprecated, ask on IRC for a better alternative");

  find_join_path_to_alias( @_[1,2] );
}

sub _collapse_cond :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  carp_unique("_collapse_cond() is deprecated, ask on IRC for a better alternative");

  shift;
  DBIx::Class::SQLMaker::Util::normalize_sqla_condition(@_);
}

sub _extract_fixed_condition_columns :DBIC_method_is_indirect_sugar {
  DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS and fail_on_internal_call;
  carp_unique("_extract_fixed_condition_columns() is deprecated, ask on IRC for a better alternative");

  shift;
  extract_equality_conditions(@_);
}

sub _resolve_ident_sources :DBIC_method_is_indirect_sugar {
  DBIx::Class::Exception->throw(
    '_resolve_ident_sources() has been removed with no replacement, '
  . 'ask for advice on IRC if this affected you'
  );
}

sub _inner_join_to_node :DBIC_method_is_indirect_sugar {
  DBIx::Class::Exception->throw(
    '_inner_join_to_node() has been removed with no replacement, '
  . 'ask for advice on IRC if this affected you'
  );
}

1;

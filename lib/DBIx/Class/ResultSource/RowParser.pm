package # hide from the pauses
  DBIx::Class::ResultSource::RowParser;

use strict;
use warnings;

use Try::Tiny;
use List::Util 'first';
use B 'perlstring';

use namespace::clean;

use base 'DBIx::Class';

# Accepts one or more relationships for the current source and returns an
# array of column names for each of those relationships. Column names are
# prefixed relative to the current source, in accordance with where they appear
# in the supplied relationships.
sub _resolve_prefetch {
  my ($self, $pre, $alias, $alias_map, $order, $pref_path) = @_;
  $pref_path ||= [];

  if (not defined $pre or not length $pre) {
    return ();
  }
  elsif( ref $pre eq 'ARRAY' ) {
    return
      map { $self->_resolve_prefetch( $_, $alias, $alias_map, $order, [ @$pref_path ] ) }
        @$pre;
  }
  elsif( ref $pre eq 'HASH' ) {
    my @ret =
    map {
      $self->_resolve_prefetch($_, $alias, $alias_map, $order, [ @$pref_path ] ),
      $self->related_source($_)->_resolve_prefetch(
         $pre->{$_}, "${alias}.$_", $alias_map, $order, [ @$pref_path, $_] )
    } keys %$pre;
    return @ret;
  }
  elsif( ref $pre ) {
    $self->throw_exception(
      "don't know how to resolve prefetch reftype ".ref($pre));
  }
  else {
    my $p = $alias_map;
    $p = $p->{$_} for (@$pref_path, $pre);

    $self->throw_exception (
      "Unable to resolve prefetch '$pre' - join alias map does not contain an entry for path: "
      . join (' -> ', @$pref_path, $pre)
    ) if (ref $p->{-join_aliases} ne 'ARRAY' or not @{$p->{-join_aliases}} );

    my $as = shift @{$p->{-join_aliases}};

    my $rel_info = $self->relationship_info( $pre );
    $self->throw_exception( $self->source_name . " has no such relationship '$pre'" )
      unless $rel_info;

    my $as_prefix = ($alias =~ /^.*?\.(.+)$/ ? $1.'.' : '');

    return map { [ "${as}.$_", "${as_prefix}${pre}.$_", ] }
      $self->related_source($pre)->columns;
  }
}

# Takes a selection list and generates a collapse-map representing
# row-object fold-points. Every relationship is assigned a set of unique,
# non-nullable columns (which may *not even be* from the same resultset)
# and the collapser will use this information to correctly distinguish
# data of individual to-be-row-objects.
sub _resolve_collapse {
  my ($self, $as, $as_fq_idx, $rel_chain, $parent_info, $node_idx_ref) = @_;

  # for comprehensible error messages put ourselves at the head of the relationship chain
  $rel_chain ||= [ $self->source_name ];

  # record top-level fully-qualified column index
  $as_fq_idx ||= { %$as };

  my ($my_cols, $rel_cols);
  for (keys %$as) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = 1;
    }
    else {
      $my_cols->{$_} = {};  # important for ||= below
    }
  }

  my $relinfo;
  # run through relationships, collect metadata, inject non-left fk-bridges from
  # *INNER-JOINED* children (if any)
  for my $rel (keys %$rel_cols) {
    my $rel_src = __get_related_source($self, $rel, $rel_cols->{$rel});

    my $inf = $self->relationship_info ($rel);

    $relinfo->{$rel}{is_single} = $inf->{attrs}{accessor} && $inf->{attrs}{accessor} ne 'multi';
    $relinfo->{$rel}{is_inner} = ( $inf->{attrs}{join_type} || '' ) !~ /^left/i;
    $relinfo->{$rel}{rsrc} = $rel_src;

    my $cond = $inf->{cond};

    if (
      ref $cond eq 'HASH'
        and
      keys %$cond
        and
      ! first { $_ !~ /^foreign\./ } (keys %$cond)
        and
      ! first { $_ !~ /^self\./ } (values %$cond)
    ) {
      for my $f (keys %$cond) {
        my $s = $cond->{$f};
        $_ =~ s/^ (?: foreign | self ) \.//x for ($f, $s);
        $relinfo->{$rel}{fk_map}{$s} = $f;

        # need to know source from *our* pov, hence $rel.
        $my_cols->{$s} ||= { via_fk => "$rel.$f" } if (
          defined $rel_cols->{$rel}{$f} # in fact selected
            and
          $relinfo->{$rel}{is_inner}
        );
      }
    }
  }

  # if the parent is already defined, assume all of its related FKs are selected
  # (even if they in fact are NOT in the select list). Keep a record of what we
  # assumed, and if any such phantom-column becomes part of our own collapser,
  # throw everything assumed-from-parent away and replace with the collapser of
  # the parent (whatever it may be)
  my $assumed_from_parent;
  unless ($parent_info->{underdefined}) {
    $assumed_from_parent->{columns} = { map
      # only add to the list if we do not already select said columns
      { ! exists $my_cols->{$_} ? ( $_ => 1 ) : () }
      values %{$parent_info->{rel_condition} || {}}
    };

    $my_cols->{$_} = { via_collapse => $parent_info->{collapse_on} }
      for keys %{$assumed_from_parent->{columns}};
  }

  # get colinfo for everything
  if ($my_cols) {
    my $ci = $self->columns_info;
    $my_cols->{$_}{colinfo} = $ci->{$_} for keys %$my_cols;
  }

  my $collapse_map;

  # try to resolve based on our columns (plus already inserted FK bridges)
  if (
    $my_cols
      and
    my $idset = $self->_identifying_column_set ({map { $_ => $my_cols->{$_}{colinfo} } keys %$my_cols})
  ) {
    # see if the resulting collapser relies on any implied columns,
    # and fix stuff up if this is the case
    my @reduced_set = grep { ! $assumed_from_parent->{columns}{$_} } @$idset;

    $collapse_map->{-node_id} = __unique_numlist(
      (@reduced_set != @$idset) ? @{$parent_info->{collapse_on}} : (),
      (map
        {
          my $fqc = join ('.',
            @{$rel_chain}[1 .. $#$rel_chain],
            ( $my_cols->{$_}{via_fk} || $_ ),
          );

          $as_fq_idx->{$fqc};
        }
        @reduced_set
      ),
    );
  }

  # Stil don't know how to collapse - keep descending down 1:1 chains - if
  # a related non-LEFT 1:1 is resolvable - its condition will collapse us
  # too
  unless ($collapse_map->{-node_id}) {
    my @candidates;

    for my $rel (keys %$relinfo) {
      next unless ($relinfo->{$rel}{is_single} && $relinfo->{$rel}{is_inner});

      if ( my $rel_collapse = $relinfo->{$rel}{rsrc}->_resolve_collapse (
        $rel_cols->{$rel},
        $as_fq_idx,
        [ @$rel_chain, $rel ],
        { underdefined => 1 }
      )) {
        push @candidates, $rel_collapse->{-node_id};
      }
    }

    # get the set with least amount of columns
    # FIXME - maybe need to implement a data type order as well (i.e. prefer several ints
    # to a single varchar)
    if (@candidates) {
      ($collapse_map->{-node_id}) = sort { scalar @$a <=> scalar @$b } (@candidates);
    }
  }

  # Still dont know how to collapse - see if the parent passed us anything
  # (i.e. reuse collapser over 1:1)
  unless ($collapse_map->{-node_id}) {
    $collapse_map->{-node_id} = $parent_info->{collapse_on}
      if $parent_info->{collapser_reusable};
  }

  # stop descending into children if we were called by a parent for first-pass
  # and don't despair if nothing was found (there may be other parallel branches
  # to dive into)
  if ($parent_info->{underdefined}) {
    return $collapse_map->{-node_id} ? $collapse_map : undef
  }
  # nothing down the chain resolved - can't calculate a collapse-map
  elsif (! $collapse_map->{-node_id}) {
    $self->throw_exception ( sprintf
      "Unable to calculate a definitive collapse column set for %s%s: fetch more unique non-nullable columns",
      $self->source_name,
      @$rel_chain > 1
        ? sprintf (' (last member of the %s chain)', join ' -> ', @$rel_chain )
        : ''
      ,
    );
  }

  # If we got that far - we are collapsable - GREAT! Now go down all children
  # a second time, and fill in the rest

  $collapse_map->{-is_optional} = 1 if $parent_info->{is_optional};
  $collapse_map->{-node_index} = ${ $node_idx_ref ||= \do { my $x = 1 } }++;  # this is *deliberately* not 0-based

  my (@id_sets, $multis_in_chain);
  for my $rel (sort keys %$relinfo) {

    $collapse_map->{$rel} = $relinfo->{$rel}{rsrc}->_resolve_collapse (
      { map { $_ => 1 } ( keys %{$rel_cols->{$rel}} ) },

      $as_fq_idx,

      [ @$rel_chain, $rel],

      {
        collapse_on => [ @{$collapse_map->{-node_id}} ],

        rel_condition => $relinfo->{$rel}{fk_map},

        is_optional => $collapse_map->{-is_optional},

        # if this is a 1:1 our own collapser can be used as a collapse-map
        # (regardless of left or not)
        collapser_reusable => $relinfo->{$rel}{is_single},
      },

      $node_idx_ref,
    );

    $collapse_map->{$rel}{-is_single} = 1 if $relinfo->{$rel}{is_single};
    $collapse_map->{$rel}{-is_optional} ||= 1 unless $relinfo->{$rel}{is_inner};
    push @id_sets, @{ $collapse_map->{$rel}{-branch_id} };
  }

  $collapse_map->{-branch_id} = __unique_numlist( @id_sets, @{$collapse_map->{-node_id}} );

  return $collapse_map;
}

# Takes an arrayref of {as} dbic column aliases and the collapse and select
# attributes from the same $rs (the slector requirement is a temporary
# workaround), and returns a coderef capable of:
# my $me_pref_clps = $coderef->([$rs->cursor->next])
# Where the $me_pref_clps arrayref is the future argument to
# ::ResultSet::_collapse_result.
#
# $me_pref_clps->[0] is always returned (even if as an empty hash with no
# rowdata), however branches of related data in $me_pref_clps->[1] may be
# pruned short of what was originally requested based on {as}, depending
# on:
#
# * If collapse is requested, a definitive collapse map is calculated for
#   every relationship "fold-point", consisting of a set of values (which
#   may not even be contained in the future 'me' of said relationship
#   (for example a cd.artist_id defines the related inner-joined artist)).
#   Thus a definedness check is carried on all collapse-condition values
#   and if at least one is undef it is assumed that we are dealing with a
#   NULLed right-side of a left-join, so we don't return a related data
#   container at all, which implies no related objects
#
# * If we are not collapsing, there is no constraint on having a selector
#   uniquely identifying all possible objects, and the user might have very
#   well requested a column that just *happens* to be all NULLs. What we do
#   in this case is fallback to the old behavior (which is a potential FIXME)
#   by always returning a data container, but only filling it with columns
#   IFF at least one of them is defined. This way we do not get an object
#   with a bunch of has_column_loaded to undef, but at the same time do not
#   further relationships based off this "null" object (e.g. in case the user
#   deliberately skipped link-table values). I am pretty sure there are some
#   tests that codify this behavior, need to find the exact testname.
#
# For an example of this coderef in action (and to see its guts) look at
# t/prefetch/_internals.t
#
# This is a huge performance win, as we call the same code for
# every row returned from the db, thus avoiding repeated method
# lookups when traversing relationships
#
# Also since the coderef is completely stateless (the returned structure is
# always fresh on every new invocation) this is a very good opportunity for
# memoization if further speed improvements are needed
#
# The way we construct this coderef is somewhat fugly, although I am not
# sure if the string eval is *that* bad of an idea. The alternative is to
# have a *very* large number of anon coderefs calling each other in a twisty
# maze, whereas the current result is a nice, smooth, single-pass function.
# In any case - the output of this thing is meticulously micro-tested, so
# any sort of rewrite should be relatively easy
#
sub _mk_row_parser {
  my ($self, $args) = @_;

  my $inflate_index = { map
    { $args->{inflate_map}[$_] => $_ }
    ( 0 .. $#{$args->{inflate_map}} )
  };

  my ($parser_src);
  if ($args->{collapse}) {

    my $collapse_map = $self->_resolve_collapse (
      # FIXME
      # only consider real columns (not functions) during collapse resolution
      # this check shouldn't really be here, as fucktards are not supposed to
      # alias random crap to existing column names anyway, but still - just in
      # case
      # FIXME !!!! - this does not yet deal with unbalanced selectors correctly
      # (it is now trivial as the attrs specify where things go out of sync)
      { map
        { ref $args->{selection}[$inflate_index->{$_}] ? () : ( $_ => $inflate_index->{$_} ) }
        keys %$inflate_index
      }
    );

    my $top_branch_idx_list = join (', ', @{$collapse_map->{-branch_id}});

    my $top_node_id_path = join ('', map
      { "{'\xFF__IDVALPOS__${_}__\xFF'}" }
      @{$collapse_map->{-node_id}}
    );

    my $rel_assemblers = __visit_infmap_collapse (
      $inflate_index, $collapse_map
    );

    $parser_src = sprintf (<<'EOS', $top_branch_idx_list, $top_node_id_path, $rel_assemblers);
### BEGIN STRING EVAL

  my ($rows_pos, $result_pos, $cur_row, @cur_row_ids, @collapse_idx, $is_new_res) = (0,0);

  # this loop is a bit arcane - the rationale is that the passed in
  # $_[0] will either have only one row (->next) or will have all
  # rows already pulled in (->all and/or unordered). Given that the
  # result can be rather large - we reuse the same already allocated
  # array, since the collapsed prefetch is smaller by definition.
  # At the end we cut the leftovers away and move on.
  while ($cur_row =
    ( ( $rows_pos >= 0 and $_[0][$rows_pos++] ) or do { $rows_pos = -1; undef } )
      ||
    ($_[1] and $_[1]->())
  ) {

    $cur_row_ids[$_] = defined $cur_row->[$_] ? $cur_row->[$_] : "\xFF\xFFN\xFFU\xFFL\xFFL\xFF\xFF"
      for (%1$s); # the top branch_id includes all id values

    $is_new_res = ! $collapse_idx[1]%2$s and (
      $_[1] and $result_pos and (unshift @{$_[2]}, $cur_row) and last
    );

    %3$s

    $_[0][$result_pos++] = $collapse_idx[1]%2$s
      if $is_new_res;
  }

  splice @{$_[0]}, $result_pos; # truncate the passed in array for cases of collapsing ->all()
### END STRING EVAL
EOS

    # change the quoted placeholders to unquoted alias-references
    $parser_src =~ s/ \' \xFF__VALPOS__(\d+)__\xFF \' /"\$cur_row->[$1]"/gex;
    $parser_src =~ s/ \' \xFF__IDVALPOS__(\d+)__\xFF \' /"\$cur_row_ids[$1]"/gex;
  }

  else {
    $parser_src = sprintf('$_ = %s for @{$_[0]}', __visit_infmap_simple(
      $inflate_index, { rsrc => $self }), # need the $rsrc to determine left-ness
    );

    # change the quoted placeholders to unquoted alias-references
    # !!! note - different var than the one above
    $parser_src =~ s/ \' \xFF__VALPOS__(\d+)__\xFF \' /"\$_->[$1]"/gex;
  }

  $parser_src;
}

sub __visit_infmap_simple {
  my ($val_idx, $args) = @_;

  my $my_cols = {};
  my $rel_cols;
  for (keys %$val_idx) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = $val_idx->{$_};
    }
    else {
      $my_cols->{$_} = $val_idx->{$_};
    }
  }
  my @relperl;
  for my $rel (sort keys %$rel_cols) {

    my $rel_rsrc = __get_related_source($args->{rsrc}, $rel, $rel_cols->{$rel});

    #my $optional = $args->{is_optional};
    #$optional ||= ($args->{rsrc}->relationship_info($rel)->{attrs}{join_type} || '') =~ /^left/i;

    push @relperl, join ' => ', perlstring($rel), __visit_infmap_simple($rel_cols->{$rel}, {
      non_top => 1,
      #is_optional => $optional,
      rsrc => $rel_rsrc,
    });

    # FIXME SUBOPTIMAL - disabled to satisfy t/resultset/inflate_result_api.t
    #if ($optional and my @branch_null_checks = map
    #  { "(! defined '\xFF__VALPOS__${_}__\xFF')" }
    #  sort { $a <=> $b } values %{$rel_cols->{$rel}}
    #) {
    #  $relperl[-1] = sprintf ( '(%s) ? ( %s => [] ) : ( %s )',
    #    join (' && ', @branch_null_checks ),
    #    perlstring($rel),
    #    $relperl[-1],
    #  );
    #}
  }

  my $me_struct = keys %$my_cols
    ? __visit_dump({ map { $_ => "\xFF__VALPOS__$my_cols->{$_}__\xFF" } (keys %$my_cols) })
    : 'undef'
  ;

  return sprintf '[%s]', join (',',
    $me_struct,
    @relperl ? sprintf ('{ %s }', join (',', @relperl)) : (),
  );
}

sub __visit_infmap_collapse {

  my ($val_idx, $collapse_map, $parent_info) = @_;

  my $my_cols = {};
  my $rel_cols;
  for (keys %$val_idx) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = $val_idx->{$_};
    }
    else {
      $my_cols->{$_} = $val_idx->{$_};
    }
  }

  my $sequenced_node_id = join ('', map
    { "{'\xFF__IDVALPOS__${_}__\xFF'}" }
    @{$collapse_map->{-node_id}}
  );

  my $me_struct = keys %$my_cols
    ? __visit_dump([{ map { $_ => "\xFF__VALPOS__$my_cols->{$_}__\xFF" } (keys %$my_cols) }])
    : undef
  ;
  my $node_idx_ref = sprintf '$collapse_idx[%d]%s', $collapse_map->{-node_index}, $sequenced_node_id;

  my $parent_idx_ref = sprintf( '$collapse_idx[%d]%s[1]{%s}',
    @{$parent_info}{qw/node_idx sequenced_node_id/},
    perlstring($parent_info->{relname}),
  ) if $parent_info;

  my @src;
  if ($collapse_map->{-node_index} == 1) {
    push @src, sprintf( '%s ||= %s;',
      $node_idx_ref,
      $me_struct,
    ) if $me_struct;
  }
  elsif ($collapse_map->{-is_single}) {
    push @src, sprintf ( '%s ||= %s%s;',
      $parent_idx_ref,
      $node_idx_ref,
      $me_struct ? " ||= $me_struct" : '',
    );
  }
  else {
    push @src, sprintf('push @{%s}, %s%s unless %s;',
      $parent_idx_ref,
      $node_idx_ref,
      $me_struct ? " ||= $me_struct" : '',
      $node_idx_ref,
    );
  }

  #my $known_defined = { %{ $parent_info->{known_defined} || {} } };
  #$known_defined->{$_}++ for @{$collapse_map->{-node_id}};

  for my $rel (sort keys %$rel_cols) {

    push @src, sprintf( '%s[1]{%s} ||= [];', $node_idx_ref, perlstring($rel) )
      unless $collapse_map->{$rel}{-is_single};

    push @src,  __visit_infmap_collapse($rel_cols->{$rel}, $collapse_map->{$rel}, {
      node_idx => $collapse_map->{-node_index},
      sequenced_node_id => $sequenced_node_id,
      relname => $rel,
      #known_defined => $known_defined,
    });

    # FIXME SUBOPTIMAL - disabled to satisfy t/resultset/inflate_result_api.t
    #if ($collapse_map->{$rel}{-is_optional} and my @null_checks = map
    #  { "(! defined '\xFF__IDVALPOS__${_}__\xFF')" }
    #  sort { $a <=> $b } grep
    #    { ! $known_defined->{$_} }
    #    @{$collapse_map->{$rel}{-node_id}}
    #) {
    #  $src[-1] = sprintf( '(%s) or %s',
    #    join (' || ', @null_checks ),
    #    $src[-1],
    #  );
    #}
  }

  join "\n", @src;
}

# adding a dep on MoreUtils *just* for this is retarded
sub __unique_numlist {
  [ sort { $a <=> $b } keys %{ {map { $_ => 1 } @_ }} ]
}

# This error must be thrown from two distinct codepaths, joining them is
# rather hard. Go for this hack instead.
sub __get_related_source {
  my ($rsrc, $rel, $relcols) = @_;
  try {
    $rsrc->related_source ($rel)
  } catch {
    $rsrc->throw_exception(sprintf(
      "Can't inflate prefetch into non-existent relationship '%s' from '%s', "
    . "check the inflation specification (columns/as) ending in '...%s.%s'.",
      $rel,
      $rsrc->source_name,
      $rel,
      (sort { length($a) <=> length ($b) } keys %$relcols)[0],
  ))};
}

# keep our own DD object around so we don't have to fitz with quoting
my $dumper_obj;
sub __visit_dump {
  # we actually will be producing functional perl code here,
  # thus no second-guessing of what these globals might have
  # been set to. DO NOT CHANGE!
  ($dumper_obj ||= do {
    require Data::Dumper;
    Data::Dumper->new([])
      ->Useperl (1)
      ->Purity (1)
      ->Pad ('')
      ->Useqq (0)
      ->Terse (1)
      ->Quotekeys (1)
      ->Deepcopy (0)
      ->Deparse (0)
      ->Maxdepth (0)
      ->Indent (0)  # faster but harder to read, perhaps leave at 1 ?
  })->Values ([$_[0]])->Dump;
}

1;

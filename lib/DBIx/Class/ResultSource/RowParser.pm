package # hide from the pauses
  DBIx::Class::ResultSource::RowParser;

use strict;
use warnings;

use base 'DBIx::Class';

use DBIx::Class::ResultSource::RowParser::Util qw(
  assemble_simple_parser
  assemble_collapsing_parser
);
use DBIx::Class::_Util qw( DUMMY_ALIASPAIR dbic_internal_try dbic_internal_catch );

use DBIx::Class::Carp;

# FIXME - this should go away
# instead Carp::Skip should export usable keywords or something like that
my $unique_carper;
BEGIN { $unique_carper = \&carp_unique }

use namespace::clean;

# Accepts a prefetch map (one or more relationships for the current source),
# returns a set of select/as pairs for each of those relationships. Columns
# are fully qualified inflation_slot names
sub _resolve_selection_from_prefetch {
  my ($self, $pre, $alias_map, $pref_path) = @_;

  # internal recursion marker
  $pref_path ||= [];

  if (not defined $pre or not length $pre) {
    return ();
  }
  elsif( ref $pre eq 'ARRAY' ) {
    map { $self->_resolve_selection_from_prefetch( $_, $alias_map, [ @$pref_path ] ) }
      @$pre;
  }
  elsif( ref $pre eq 'HASH' ) {
    map {
      $self->_resolve_selection_from_prefetch($_, $alias_map, [ @$pref_path ] ),
      $self->related_source($_)->_resolve_selection_from_prefetch(
         $pre->{$_}, $alias_map, [ @$pref_path, $_] )
    } keys %$pre;
  }
  elsif( ref $pre ) {
    $self->throw_exception(
      "don't know how to resolve prefetch reftype ".ref($pre));
  }
  else {
    my $p = $alias_map;
    $p = $p->{$_} for @$pref_path, $pre;

    $self->throw_exception (
      "Unable to resolve prefetch '$pre' - join alias map does not contain an entry for path: "
      . join (' -> ', @$pref_path, $pre)
    ) if (ref $p->{-join_aliases} ne 'ARRAY' or not @{$p->{-join_aliases}} );

    # this shift() is critical - it is what allows prefetch => [ (foo) x 2 ] to work
    my $src_alias = shift @{$p->{-join_aliases}};

    # ordered [select => as] pairs
    map { [
      "${src_alias}.$_" => join ( '.',
        @$pref_path,
        $pre,
        $_,
      )
    ] } $self->related_source($pre)->columns;
  }
}

sub _resolve_prefetch {
  carp_unique(
    'There is no good reason to call this internal deprecated method - '
  . 'please open a ticket detailing your usage, so that a better plan can '
  . 'be devised for your case. In either case _resolve_prefetch() is '
  . 'deprecated in favor of _resolve_selection_from_prefetch(), which has '
  . 'a greatly simplified arglist.'
  );

  $_[0]->_resolve_selection_from_prefetch( $_[1], $_[3] );
}


# Takes an arrayref of {as} dbic column aliases and the collapse and select
# attributes from the same $rs (the selector requirement is a temporary
# workaround... I hope), and returns a coderef capable of:
# my $me_pref_clps = $coderef->([$rs->cursor->next/all])
# Where the $me_pref_clps arrayref is the future argument to inflate_result()
#
# For an example of this coderef in action (and to see its guts) look at
# t/resultset/rowparser_internals.t
#
# This is a huge performance win, as we call the same code for every row
# returned from the db, thus avoiding repeated method lookups when traversing
# relationships
#
# Also since the coderef is completely stateless (the returned structure is
# always fresh on every new invocation) this is a very good opportunity for
# memoization if further speed improvements are needed
#
# The way we construct this coderef is somewhat fugly, although the result is
# really worth it. The final coderef does not perform any kind of recursion -
# the entire nested structure constructor is rolled out into a single scope.
#
# In any case - the output of this thing is meticulously micro-tested, so
# any sort of adjustment/rewrite should be relatively easy (fsvo relatively)
#
sub _mk_row_parser {
  # $args and $attrs are separated to delineate what is core collapser stuff and
  # what is dbic $rs specific
  my ($self, $args, $attrs) = @_;

  die "HRI without pruning makes zero sense"
  if ( $args->{hri_style} && ! $args->{prune_null_branches} );

  my %common = (
    hri_style => $args->{hri_style},
    prune_null_branches => $args->{prune_null_branches},
    val_index => { map
      { $args->{inflate_map}[$_] => $_ }
      ( 0 .. $#{$args->{inflate_map}} )
    },
  );

  my $src = (! $args->{collapse} ) ? assemble_simple_parser(\%common) : do {
    my $collapse_map = $self->_resolve_collapse ({
      # FIXME
      # only consider real columns (not functions) during collapse resolution
      # this check shouldn't really be here, as fucktards are not supposed to
      # alias random crap to existing column names anyway, but still - just in
      # case
      # FIXME !!!! - this does not yet deal with unbalanced selectors correctly
      # (it is now trivial as the attrs specify where things go out of sync
      # needs MOAR tests)
      as => { map
        { ref $attrs->{select}[$common{val_index}{$_}] ? () : ( $_ => $common{val_index}{$_} ) }
        keys %{$common{val_index}}
      },
      premultiplied => $args->{premultiplied},
    });

    assemble_collapsing_parser({
      %common,
      collapse_map => $collapse_map,
    });
  };

  utf8::upgrade($src)
    if DBIx::Class::_ENV_::STRESSTEST_UTF8_UPGRADE_GENERATED_COLLAPSER_SOURCE;

  $src;
}


# Takes an arrayref selection list and generates a collapse-map representing
# row-object fold-points. Every relationship is assigned a set of unique,
# non-nullable columns (which may *not even be* from the same resultset)
# and the collapser will use this information to correctly distinguish
# data of individual to-be-row-objects. See t/resultset/rowparser_internals.t
# for extensive RV examples
sub _resolve_collapse {
  my ($self, $args, $common_args) = @_;

  # for comprehensible error messages put ourselves at the head of the relationship chain
  $args->{_rel_chain} ||= [ $self->source_name ];

  # record top-level fully-qualified column index, signify toplevelness
  unless ($common_args->{_as_fq_idx}) {
    $common_args->{_as_fq_idx} = { %{$args->{as}} };
    $args->{_is_top_level} = 1;
  };

  my ($my_cols, $rel_cols, $native_cols);
  for (keys %{$args->{as}}) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = 1;
    }
    else {
      $native_cols->{$_} = $my_cols->{$_} = {};  # important for ||='s below
    }
  }

  my $relinfo;
  # run through relationships, collect metadata
  for my $rel (keys %$rel_cols) {
    my $inf = $self->relationship_info ($rel);

    $relinfo->{$rel} = {
      is_single => ( $inf->{attrs}{accessor} && $inf->{attrs}{accessor} ne 'multi' ),
      is_inner => ( ( $inf->{attrs}{join_type} || '' ) !~ /^left/i),
      rsrc => $self->related_source($rel),
      fk_map => (
        dbic_internal_try {
          $self->resolve_relationship_condition(
            rel_name => $rel,

            # an API where these are optional would be too cumbersome,
            # instead always pass in some dummy values
            DUMMY_ALIASPAIR,
          )->{identity_map},
        }
        dbic_internal_catch {

          $unique_carper->(
            "Resolution of relationship '$rel' failed unexpectedly, "
          . 'please relay the following error and seek assistance via '
          . DBIx::Class::_ENV_::HELP_URL . ". Encountered error: $_"
          );

          # RV
          +{}
        }
      ),
    };
  }

  # inject non-left fk-bridges from *INNER-JOINED* children (if any)
  for my $rel (grep { $relinfo->{$_}{is_inner} } keys %$relinfo) {
    my $ri = $relinfo->{$rel};
    for (keys %{$ri->{fk_map}} ) {
      # need to know source from *our* pov, hence $rel.col
      $my_cols->{$_} ||= { via_fk => "$rel.$ri->{fk_map}{$_}" }
        if defined $rel_cols->{$rel}{$ri->{fk_map}{$_}} # in fact selected
    }
  }

  # if the parent is already defined *AND* we have an inner reverse relationship
  # (i.e. do not exist without it) , assume all of its related FKs are selected
  # (even if they in fact are NOT in the select list). Keep a record of what we
  # assumed, and if any such phantom-column becomes part of our own collapser,
  # throw everything assumed-from-parent away and replace with the collapser of
  # the parent (whatever it may be)
  my $assumed_from_parent;
  if ( ! $args->{_parent_info}{underdefined} and ! $args->{_parent_info}{rev_rel_is_optional} ) {
    for my $col ( values %{$args->{_parent_info}{rel_condition} || {}} ) {
      next if exists $my_cols->{$col};
      $my_cols->{$col} = {};
      $assumed_from_parent->{columns}{$col}++;
    }
  }

  # get colinfo for everything
  if ($my_cols) {
    my $ci = $self->columns_info;
    $my_cols->{$_}{colinfo} = $ci->{$_} for keys %$my_cols;
  }

  my $collapse_map;

  # first try to reuse the parent's collapser (i.e. reuse collapser over 1:1)
  # (makes for a leaner coderef later)
  if(
    ! $collapse_map->{-identifying_columns}
      and
    $args->{_parent_info}{collapser_reusable}
  ) {
    $collapse_map->{-identifying_columns} = $args->{_parent_info}{collapse_on_idcols}
  }

  # Still don't know how to collapse - in case we are a *single* relationship
  # AND our parent is defined AND we have any *native* non-nullable pieces: then
  # we are still good to go
  # NOTE: it doesn't matter if the nonnullable set is unique or not - it will be
  # made unique by the parents identifying cols
  if(
    ! $collapse_map->{-identifying_columns}
      and
    $args->{_parent_info}{is_single}
      and
    @{ $args->{_parent_info}{collapse_on_idcols} }
      and
    ( my @native_nonnull_cols = grep {
      $native_cols->{$_}{colinfo}
        and
      ! $native_cols->{$_}{colinfo}{is_nullable}
    } keys %$native_cols )
  ) {

    $collapse_map->{-identifying_columns} = [ __unique_numlist(
      @{ $args->{_parent_info}{collapse_on_idcols}||[] },

      # FIXME - we don't really need *all* of the columns, $our_nonnull_cols[0]
      # is sufficient. However map the entire thing to engage the extra nonnull
      # explicit checks, just to be on the safe side
      # Remove some day in the future
      (map
        {
          $common_args->{_as_fq_idx}{join ('.',
            @{$args->{_rel_chain}}[1 .. $#{$args->{_rel_chain}}],
            $_,
          )}
        }
        @native_nonnull_cols
      ),
    )];
  }

  # Still don't know how to collapse - try to resolve based on our columns (plus already inserted FK bridges)
  if (
    ! $collapse_map->{-identifying_columns}
      and
    $my_cols
      and
    my $idset = $self->_identifying_column_set ({map { $_ => $my_cols->{$_}{colinfo} } keys %$my_cols})
  ) {
    # see if the resulting collapser relies on any implied columns,
    # and fix stuff up if this is the case
    my @reduced_set = grep { ! $assumed_from_parent->{columns}{$_} } @$idset;

    $collapse_map->{-identifying_columns} = [ __unique_numlist(
      @{ $args->{_parent_info}{collapse_on_idcols}||[] },

      (map
        {
          my $fqc = join ('.',
            @{$args->{_rel_chain}}[1 .. $#{$args->{_rel_chain}}],
            ( $my_cols->{$_}{via_fk} || $_ ),
          );

          $common_args->{_as_fq_idx}->{$fqc};
        }
        @reduced_set
      ),
    )];
  }

  # Stil don't know how to collapse - keep descending down 1:1 chains - if
  # a related non-LEFT 1:1 is resolvable - its condition will collapse us
  # too
  unless ($collapse_map->{-identifying_columns}) {
    my @candidates;

    for my $rel (keys %$relinfo) {
      next unless ($relinfo->{$rel}{is_single} && $relinfo->{$rel}{is_inner});

      if ( my $rel_collapse = $relinfo->{$rel}{rsrc}->_resolve_collapse ({
        as => $rel_cols->{$rel},
        _rel_chain => [ @{$args->{_rel_chain}}, $rel ],
        _parent_info => { underdefined => 1 },
      }, $common_args)) {
        push @candidates, $rel_collapse->{-identifying_columns};
      }
    }

    # get the set with least amount of columns
    # FIXME - maybe need to implement a data type order as well (i.e. prefer several ints
    # to a single varchar)
    if (@candidates) {
      ($collapse_map->{-identifying_columns}) = sort { scalar @$a <=> scalar @$b } (@candidates);
    }
  }

  # Stil don't know how to collapse, and we are the root node. Last ditch
  # effort in case we are *NOT* premultiplied.
  # Run through *each multi* all the way down, left or not, and all
  # *left* singles (a single may become a multi underneath) . When everything
  # gets back see if all the rels link to us definitively. If this is the
  # case we are good - either one of them will define us, or if all are NULLs
  # we know we are "unique" due to the "non-premultiplied" check
  if (
    ! $collapse_map->{-identifying_columns}
      and
    ! $args->{premultiplied}
      and
    $args->{_is_top_level}
  ) {
    my (@collapse_sets, $uncollapsible_chain);

    for my $rel (keys %$relinfo) {

      # we already looked at these higher up
      next if ($relinfo->{$rel}{is_single} && $relinfo->{$rel}{is_inner});

      if (my $clps = $relinfo->{$rel}{rsrc}->_resolve_collapse ({
        as => $rel_cols->{$rel},
        _rel_chain => [ @{$args->{_rel_chain}}, $rel ],
        _parent_info => { underdefined => 1 },
      }, $common_args) ) {

        # for singles use the idcols wholesale (either there or not)
        if ($relinfo->{$rel}{is_single}) {
          push @collapse_sets, $clps->{-identifying_columns};
        }
        elsif (! $relinfo->{$rel}{fk_map}) {
          $uncollapsible_chain = 1;
          last;
        }
        else {
          my $defined_cols_parent_side;

          for my $fq_col ( grep { /^$rel\.[^\.]+$/ } keys %{$args->{as}} ) {
            my ($col) = $fq_col =~ /([^\.]+)$/;

            $defined_cols_parent_side->{$_} = $args->{as}{$fq_col} for grep
              { $relinfo->{$rel}{fk_map}{$_} eq $col }
              keys %{$relinfo->{$rel}{fk_map}}
            ;
          }

          if (my $set = $self->_identifying_column_set([ keys %$defined_cols_parent_side ]) ) {
            push @collapse_sets, [ sort map { $defined_cols_parent_side->{$_} } @$set ];
          }
          else {
            $uncollapsible_chain = 1;
            last;
          }
        }
      }
      else {
        $uncollapsible_chain = 1;
        last;
      }
    }

    unless ($uncollapsible_chain) {
      # if we got here - we are good to go, but the construction is tricky
      # since our children will want to include our collapse criteria - we
      # don't give them anything (safe, since they are all collapsible on their own)
      # in addition we record the individual collapse possibilities
      # of all left children node collapsers, and merge them in the rowparser
      # coderef later
      $collapse_map->{-identifying_columns} = [];
      $collapse_map->{-identifying_columns_variants} = [ sort {
        (scalar @$a) <=> (scalar @$b)
          or
        (
          # Poor man's max()
          ( sort { $b <=> $a } @$a )[0]
            <=>
          ( sort { $b <=> $a } @$b )[0]
        )
      } @collapse_sets ];
    }
  }

  # stop descending into children if we were called by a parent for first-pass
  # and don't despair if nothing was found (there may be other parallel branches
  # to dive into)
  if ($args->{_parent_info}{underdefined}) {
    return $collapse_map->{-identifying_columns} ? $collapse_map : undef
  }
  # nothing down the chain resolved - can't calculate a collapse-map
  elsif (! $collapse_map->{-identifying_columns}) {
    $self->throw_exception ( sprintf
      "Unable to calculate a definitive collapse column set for %s%s: fetch more unique non-nullable columns",
      $self->source_name,
      @{$args->{_rel_chain}} > 1
        ? sprintf (' (last member of the %s chain)', join ' -> ', @{$args->{_rel_chain}} )
        : ''
      ,
    );
  }

  # If we got that far - we are collapsable - GREAT! Now go down all children
  # a second time, and fill in the rest

  $collapse_map->{-identifying_columns} = [ __unique_numlist(
    @{ $args->{_parent_info}{collapse_on_idcols}||[] },
    @{ $collapse_map->{-identifying_columns} },
  )];

  for my $rel (sort keys %$relinfo) {

    $collapse_map->{$rel} = $relinfo->{$rel}{rsrc}->_resolve_collapse ({
      as => { map { $_ => 1 } ( keys %{$rel_cols->{$rel}} ) },
      _rel_chain => [ @{$args->{_rel_chain}}, $rel],
      _parent_info => {
        # shallow copy
        collapse_on_idcols => [ @{$collapse_map->{-identifying_columns}} ],

        rel_condition => $relinfo->{$rel}{fk_map},

        is_optional => ! $relinfo->{$rel}{is_inner},

        is_single => $relinfo->{$rel}{is_single},

        # if there is at least one *inner* reverse relationship ( meaning identity-only )
        # we can safely assume that the child can not exist without us
        rev_rel_is_optional => (
          ( grep {
            ($_->{attrs}{join_type}||'') !~ /^left/i
          } values %{ $self->reverse_relationship_info($rel) } )
            ? 0
            : 1
        ),

        # if this is a 1:1 our own collapser can be used as a collapse-map
        # (regardless of left or not)
        collapser_reusable => (
          $relinfo->{$rel}{is_single}
            &&
          $relinfo->{$rel}{is_inner}
            &&
          @{$collapse_map->{-identifying_columns}}
        ) ? 1 : 0,
      },
    }, $common_args );

    $collapse_map->{$rel}{-is_single} = 1 if $relinfo->{$rel}{is_single};
    $collapse_map->{$rel}{-is_optional} ||= 1 unless $relinfo->{$rel}{is_inner};
  }

  return $collapse_map;
}

# adding a dep on MoreUtils *just* for this is retarded
sub __unique_numlist {
  sort { $a <=> $b } keys %{ {map { $_ => 1 } @_ }}
}

1;

package # hide from the pauses
  DBIx::Class::ResultSource::RowParser::Util;

use strict;
use warnings;

use DBIx::Class::_Util qw( perlstring dump_value );

use constant HAS_DOR => ( ( DBIx::Class::_ENV_::PERL_VERSION < 5.010 ) ? 0 : 1 );

use base 'Exporter';
our @EXPORT_OK = qw(
  assemble_simple_parser
  assemble_collapsing_parser
);

# working title - we are hoping to extract this eventually...
our $null_branch_class = 'DBIx::ResultParser::RelatedNullBranch';

sub __wrap_in_strictured_scope {
  "sub { use strict; use warnings; use warnings FATAL => 'uninitialized';\n$_[0]\n  }"
}

sub assemble_simple_parser {
  #my ($args) = @_;

  # the non-collapsing assembler is easy
  # FIXME SUBOPTIMAL there could be a yet faster way to do things here, but
  # need to try an actual implementation and benchmark it:
  #
  # <timbunce_> First setup the nested data structure you want for each row
  #   Then call bind_col() to alias the row fields into the right place in
  #   the data structure, then to fetch the data do:
  # push @rows, dclone($row_data_struct) while ($sth->fetchrow);
  #

  __wrap_in_strictured_scope( sprintf
    '$_ = %s for @{$_[0]}',
    __visit_infmap_simple( $_[0] )
  );
}

# the simple non-collapsing nested structure recursor
sub __visit_infmap_simple {
  my $args = shift;

  my $my_cols = {};
  my $rel_cols;
  for (keys %{$args->{val_index}}) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = $args->{val_index}{$_};
    }
    else {
      $my_cols->{$_} = $args->{val_index}{$_};
    }
  }

  my @relperl;
  for my $rel (sort keys %$rel_cols) {

    my $rel_struct = __visit_infmap_simple({ %$args,
      val_index => $rel_cols->{$rel},
    });

    if (keys %$my_cols) {

      my $branch_null_checks = join ' && ', map
        { "( ! defined \$_->[$_] )" }
        sort { $a <=> $b } values %{$rel_cols->{$rel}}
      ;

      if ($args->{prune_null_branches}) {
        $rel_struct = sprintf ( '( (%s) ? undef : %s )',
          $branch_null_checks,
          $rel_struct,
        );
      }
      else {
        $rel_struct = sprintf ( '( (%s) ? bless( (%s), %s ) : %s )',
          $branch_null_checks,
          $rel_struct,
          perlstring($null_branch_class),
          $rel_struct,
        );
      }
    }

    push @relperl, sprintf '( %s => %s )',
      perlstring($rel),
      $rel_struct,
    ;

  }

  my $me_struct;
  $me_struct = __result_struct_to_source($my_cols) if keys %$my_cols;

  if ($args->{hri_style}) {
    $me_struct =~ s/^ \s* \{ | \} \s* $//gx
      if $me_struct;

    return sprintf '{ %s }', join (', ', $me_struct||(), @relperl);
  }
  else {
    return sprintf '[%s]', join (',',
      $me_struct || 'undef',
      @relperl ? sprintf ('{ %s }', join (',', @relperl)) : (),
    );
  }
}

sub assemble_collapsing_parser {
  my $args = shift;

  my ($top_node_key, $top_node_key_assembler, $variant_idcols);

  if (scalar @{$args->{collapse_map}{-identifying_columns}}) {
    $top_node_key = join ('', map
      { "{ \$cur_row_ids{$_} }" }
      @{$args->{collapse_map}{-identifying_columns}}
    );

    $top_node_key_assembler = '';
  }
  elsif( my @variants = @{$args->{collapse_map}{-identifying_columns_variants}} ) {

    my @path_parts = map { sprintf
      "( ( defined \$cur_row_data->[%d] ) && (join qq(\xFF), '', %s, '') )",
      $_->[0],  # checking just first is enough - one ID defined, all defined
      ( join ', ', map { $variant_idcols->{$_} = 1; " \$cur_row_ids{$_} " } @$_ ),
    } @variants;

    my $virtual_column_idx = (scalar keys %{$args->{val_index}} ) + 1;

    $top_node_key = "{ \$cur_row_ids{$virtual_column_idx} }";

    $top_node_key_assembler = sprintf "( \$cur_row_ids{%d} = (%s) ),",
      $virtual_column_idx,
      "\n" . join( "\n  or\n", @path_parts, qq{"\0\$rows_pos\0"} )
    ;

    $args->{collapse_map} = {
      %{$args->{collapse_map}},
      -custom_node_key => $top_node_key,
    };
  }
  else {
    DBIx::Class::Exception->throw(
     'Unexpected collapse map contents: ' . dump_value $args->{collapse_map},
      1,
    )
  }

  my ($data_assemblers, $stats) = __visit_infmap_collapse ($args);

  # variants do not necessarily overlap with true idcols
  my @row_ids = sort { $a <=> $b } keys %{ {
    %{ $variant_idcols || {} },
    %{ $stats->{idcols_seen} },
  } };

  my $row_id_defs = sprintf "( \@cur_row_ids{( %s )} = (\n%s\n ) ),",
    join (', ', @row_ids ),
    # in case we prune - we will never hit undefs/NULLs as pigeon-hole-criteria
    ( $args->{prune_null_branches}
      ? sprintf( '@{$cur_row_data}[( %s )]', join ', ', @row_ids )
      : join (",\n", map {
        $stats->{nullchecks}{mandatory}{$_}
          ? qq!( \$cur_row_data->[$_] )!
          : do {
            my $quoted_null_val = qq("\0NULL\xFF\${rows_pos}\xFF${_}\0");
            HAS_DOR
              ? qq!( \$cur_row_data->[$_] // $quoted_null_val )!
              : qq!( defined(\$cur_row_data->[$_]) ? \$cur_row_data->[$_] : $quoted_null_val )!
          }
      } @row_ids)
    )
  ;

  my $null_checks = '';

  for my $c ( sort { $a <=> $b } keys %{$stats->{nullchecks}{mandatory}} ) {
    $null_checks .= sprintf <<'EOS', $c
( defined( $cur_row_data->[%1$s] ) or $_[3]->{%1$s} = 1 ),

EOS
  }

  for my $set ( @{ $stats->{nullchecks}{from_first_encounter} || [] } ) {
    my @sub_checks;

    for my $i (0 .. $#$set - 1) {

      push @sub_checks, sprintf
        '( not defined $cur_row_data->[%1$s] ) ? ( %2$s or ( $_[3]->{%1$s} = 1 ) )',
        $set->[$i],
        join( ' and ', map
          { "( not defined \$cur_row_data->[$set->[$_]] )" }
          ( $i+1 .. $#$set )
        ),
      ;
    }

    $null_checks .= "(\n @{[ join qq(\n: ), @sub_checks, '()' ]} \n),\n";
  }

  for my $set ( @{ $stats->{nullchecks}{all_or_nothing} || [] } ) {

    $null_checks .= sprintf "(\n( %s )\n  or\n(\n%s\n)\n),\n",
      join ( ' and ', map
        { "( not defined \$cur_row_data->[$_] )" }
        sort { $a <=> $b } keys %$set
      ),
      join ( ",\n", map
        { "( defined(\$cur_row_data->[$_]) or \$_[3]->{$_} = 1 )" }
        sort { $a <=> $b } keys %$set
      ),
    ;
  }

  # If any of the above generators produced something, we need to add the
  # final "if seen any violations - croak" part
  # Do not throw from within the string eval itself as it does not have
  # the necessary metadata to construct a nice exception text. As a bonus
  # we get to entirely avoid https://github.com/Test-More/Test2/issues/16
  # and https://rt.perl.org/Public/Bug/Display.html?id=127774

  $null_checks .= <<'EOS' if $null_checks;

( keys %{$_[3]} and (
    ( @{$_[2]} = $cur_row_data ),
    ( $result_pos = 0 ),
    last
) ),
EOS


  my $parser_src = sprintf (<<'EOS', $null_checks, $row_id_defs, $top_node_key_assembler, $top_node_key, join( "\n", @$data_assemblers ) );
### BEGIN LITERAL STRING EVAL
  my $rows_pos = 0;
  my ($result_pos, @collapse_idx, $cur_row_data, %%cur_row_ids );

  # this loop is a bit arcane - the rationale is that the passed in
  # $_[0] will either have only one row (->next) or will have all
  # rows already pulled in (->all and/or unordered). Given that the
  # result can be rather large - we reuse the same already allocated
  # array, since the collapsed prefetch is smaller by definition.
  # At the end we cut the leftovers away and move on.
  while ($cur_row_data = (
    (
      $rows_pos >= 0
        and
      (
        $_[0][$rows_pos++]
          or
        # It may be tempting to drop the -1 and undef $rows_pos instead
        # thus saving the >= comparison above as well
        # However NULL-handlers and underdefined root markers both use
        # $rows_pos as a last-resort-uniqueness marker (it either is
        # monotonically increasing while we parse ->all, or is set at
        # a steady -1 when we are dealing with a single root node). For
        # the time being the complication of changing all callsites seems
        # overkill, for what is going to be a very modest saving of ops
        ( ($rows_pos = -1), undef )
      )
    )
      or
    ( $_[1] and $_[1]->() )
  ) ) {

    # column_info metadata historically hasn't been too reliable.
    # We need to start fixing this somehow (the collapse resolver
    # can't work without it). Add explicit checks for several cases
    # of "unexpected NULL", based on the metadata returned by
    # __visit_infmap_collapse
    #
    # FIXME - this is a temporary kludge that reduces performance
    # It is however necessary for the time being, until way into the
    # future when the extra errors clear out all invalid metadata
%s

    # due to left joins some of the ids may be NULL/undef, and
    # won't play well when used as hash lookups
    # we also need to differentiate NULLs on per-row/per-col basis
    # (otherwise folding of optional 1:1s will be greatly confused
    #
    # the undef checks may or may not be there depending on whether
    # we prune or not
%s

    # in the case of an underdefined root - calculate the virtual id (otherwise no code at all)
%s

    # if we were supplied a coderef - we are collapsing lazily (the set
    # is ordered properly)
    # as long as we have a result already and the next result is new we
    # return the pre-read data and bail
( $_[1] and $result_pos and ! $collapse_idx[0]%s and (unshift @{$_[2]}, $cur_row_data) and last ),

    # the rel assemblers
%s

  }

  $#{$_[0]} = $result_pos - 1; # truncate the passed in array to where we filled it with results
### END LITERAL STRING EVAL
EOS

  __wrap_in_strictured_scope($parser_src);
}


# the collapsing nested structure recursor
sub __visit_infmap_collapse {
  my $args = {%{ shift() }};

  my $cur_node_idx = ${ $args->{-node_idx_counter} ||= \do { my $x = 0} }++;

  $args->{-mandatory_ids} ||= {};
  $args->{-seen_ids} ||= {};
  $args->{-all_or_nothing_sets} ||= [];
  $args->{-null_from} ||= [];

  $args->{-seen_ids}{$_} = 1
    for @{$args->{collapse_map}->{-identifying_columns}};

  my $node_specific_ids = { map { $_ => 1 } grep
    { ! $args->{-parent_ids}{$_} }
    @{$args->{collapse_map}->{-identifying_columns}}
  };

  if (not ( $args->{-chain_is_optional} ||= $args->{collapse_map}{-is_optional} ) ) {
    $args->{-mandatory_ids}{$_} = 1
      for @{$args->{collapse_map}->{-identifying_columns}};
  }
  elsif ( keys %$node_specific_ids > 1 ) {
    push @{$args->{-all_or_nothing_sets}}, $node_specific_ids;
  }

  my ($my_cols, $rel_cols) = {};
  for ( keys %{$args->{val_index}} ) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = $args->{val_index}{$_};
    }
    else {
      $my_cols->{$_} = $args->{val_index}{$_};
    }
  }


  if ($args->{hri_style}) {
    delete $my_cols->{$_} for grep { $rel_cols->{$_} } keys %$my_cols;
  }

  my $me_struct;
  $me_struct = __result_struct_to_source($my_cols, 1) if keys %$my_cols;

  $me_struct = sprintf( '[ %s ]', $me_struct||'' )
    unless $args->{hri_style};


  my $node_key = $args->{collapse_map}->{-custom_node_key} || join ('', map
    { "{ \$cur_row_ids{$_} }" }
    @{$args->{collapse_map}->{-identifying_columns}}
  );
  my $node_idx_slot = sprintf '$collapse_idx[%d]%s', $cur_node_idx, $node_key;


  my @src;

  if ($cur_node_idx == 0) {
    push @src, sprintf( '( %s %s $_[0][$result_pos++] = %s ),',
      $node_idx_slot,
      (HAS_DOR ? '//=' : '||='),
      $me_struct || '{}',
    );
  }
  else {
    my $parent_attach_slot = sprintf( '$collapse_idx[%d]%s%s{%s}',
      @{$args}{qw/-parent_node_idx -parent_node_key/},
      $args->{hri_style} ? '' : '[1]',
      perlstring($args->{-node_rel_name}),
    );

    if ($args->{collapse_map}->{-is_single}) {
      push @src, sprintf ( '( %s %s %s = %s ),',
        $parent_attach_slot,
        (HAS_DOR ? '//=' : '||='),
        $node_idx_slot,
        $me_struct || '{}',
      );
    }
    else {
      push @src, sprintf('( (! %s) and push @{%s}, %s = %s ),',
        $node_idx_slot,
        $parent_attach_slot,
        $node_idx_slot,
        $me_struct || '{}',
      );
    }
  }

  my $known_present_ids = { map { $_ => 1 } @{$args->{collapse_map}{-identifying_columns}} };
  my $rel_src;

  for my $rel (sort keys %$rel_cols) {

    my $relinfo = $args->{collapse_map}{$rel};

    ($rel_src) = __visit_infmap_collapse({ %$args,
      val_index => $rel_cols->{$rel},
      collapse_map => $relinfo,
      -parent_node_idx => $cur_node_idx,
      -parent_node_key => $node_key,
      -parent_id_path => [ @{$args->{-parent_id_path}||[]}, sort { $a <=> $b } keys %$node_specific_ids ],
      -parent_ids => { map { %$_ } $node_specific_ids, $args->{-parent_ids}||{} },
      -node_rel_name => $rel,
    });

    my $rel_src_pos = $#src + 1;
    push @src, @$rel_src;

    if (
      $relinfo->{-is_optional}
    ) {

      my ($first_distinct_child_idcol) = grep
        { ! $known_present_ids->{$_} }
        @{$relinfo->{-identifying_columns}}
      ;

      DBIx::Class::Exception->throw(
        "An optional node *without* a distinct identifying set shouldn't be possible: " . dump_value $args->{collapse_map},
        1,
      ) unless defined $first_distinct_child_idcol;

      if ($args->{prune_null_branches}) {

        # start of wrap of the entire chain in a conditional
        splice @src, $rel_src_pos, 0, sprintf "( ( ! defined %s )\n  ? %s%s{%s} = %s\n  : do {",
          "\$cur_row_data->[$first_distinct_child_idcol]",
          $node_idx_slot,
          $args->{hri_style} ? '' : '[1]',
          perlstring($rel),
          ($args->{hri_style} && $relinfo->{-is_single}) ? 'undef' : '[]'
        ;

        # end of wrap
        push @src, '} ),'
      }
      else {

        splice @src, $rel_src_pos + 1, 0, sprintf ( '( (defined %s) or bless (%s[1]{%s}, %s) ),',
          "\$cur_row_data->[$first_distinct_child_idcol]",
          $node_idx_slot,
          perlstring($rel),
          perlstring($null_branch_class),
        );
      }
    }
  }

  if (

    # calculation only valid for leaf nodes
    ! values %$rel_cols

      and

    # child of underdefined path doesn't leave us anything to test
    @{$args->{-parent_id_path} || []}

      and

    (my @nullable_portion = grep
      { ! $args->{-mandatory_ids}{$_} }
      (
        @{$args->{-parent_id_path}},
        sort { $a <=> $b } keys %$node_specific_ids
      )
    ) > 1
  ) {
    # there may be 1:1 overlap with a specific all_or_nothing
    push @{$args->{-null_from}}, \@nullable_portion unless grep
      {
        my $a_o_n_set = $_;

        keys %$a_o_n_set == @nullable_portion
          and
        ! grep { ! $a_o_n_set->{$_} } @nullable_portion
      }
      @{ $args->{-all_or_nothing_sets} || [] }
    ;
  }

  return (
    \@src,
    ( $cur_node_idx != 0 ) ? () : {
      idcols_seen => $args->{-seen_ids},
      nullchecks => {
        ( keys %{$args->{-mandatory_ids} }
          ? ( mandatory => $args->{-mandatory_ids} )
          : ()
        ),
        ( @{$args->{-all_or_nothing_sets}}
          ? ( all_or_nothing => $args->{-all_or_nothing_sets} )
          : ()
        ),
        ( @{$args->{-null_from}}
          ? ( from_first_encounter => $args->{-null_from} )
          : ()
        ),
      },
    },
  );
}

sub __result_struct_to_source {
  my ($data, $is_collapsing) = @_;

  sprintf( '{ %s }',
    join (', ', map {
      sprintf ( "%s => %s",
        perlstring($_),
        $is_collapsing
          ? "\$cur_row_data->[$data->{$_}]"
          : "\$_->[ $data->{$_} ]"
      )
    } sort keys %{$data}
    )
  );
}

1;

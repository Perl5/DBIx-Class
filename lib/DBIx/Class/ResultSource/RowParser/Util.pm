package # hide from the pauses
  DBIx::Class::ResultSource::RowParser::Util;

use strict;
use warnings;

use B 'perlstring';

use base 'Exporter';
our @EXPORT_OK = qw(
  assemble_simple_parser
  assemble_collapsing_parser
);

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
  my $parser_src = sprintf('$_ = %s for @{$_[0]}', __visit_infmap_simple($_[0]) );

  # change the quoted placeholders to unquoted alias-references
  $parser_src =~ s/ \' \xFF__VALPOS__(\d+)__\xFF \' /"\$_->[$1]"/gex;

  return $parser_src;
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

    # DISABLEPRUNE
    #my $optional = $args->{is_optional};
    #$optional ||= ($args->{rsrc}->relationship_info($rel)->{attrs}{join_type} || '') =~ /^left/i;

    push @relperl, join ' => ', perlstring($rel), __visit_infmap_simple({ %$args,
      val_index => $rel_cols->{$rel},
      # DISABLEPRUNE
      #non_top => 1,
      #is_optional => $optional,
    });

    # FIXME SUBOPTIMAL DISABLEPRUNE - disabled to satisfy t/resultset/inflate_result_api.t
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

sub assemble_collapsing_parser {
  my $args = shift;

  my ($top_node_key, $top_node_key_assembler);

  if (scalar @{$args->{collapse_map}{-identifying_columns}}) {
    $top_node_key = join ('', map
      { "{'\xFF__IDVALPOS__${_}__\xFF'}" }
      @{$args->{collapse_map}{-identifying_columns}}
    );
  }
  elsif( my @variants = @{$args->{collapse_map}{-identifying_columns_variants}} ) {

    my @path_parts = map { sprintf
      "( ( defined '\xFF__VALPOS__%d__\xFF' ) && (join qq(\xFF), '', %s, '') )",
      $_->[0],  # checking just first is enough - one defined, all defined
      ( join ', ', map { "'\xFF__VALPOS__${_}__\xFF'" } @$_ ),
    } @variants;

    my $virtual_column_idx = (scalar keys %{$args->{val_index}} ) + 1;

    $top_node_key_assembler = sprintf '$cur_row_ids{%d} = (%s);',
      $virtual_column_idx,
      "\n" . join( "\n  or\n", @path_parts, qq{"\0\$rows_pos\0"} );

    $top_node_key = sprintf '{$cur_row_ids{%d}}', $virtual_column_idx;

    $args->{collapse_map} = {
      %{$args->{collapse_map}},
      -custom_node_key => $top_node_key,
    };

  }
  else {
    die('Unexpected collapse map contents');
  }

  my ($data_assemblers, $stats) = __visit_infmap_collapse ($args);

  my $list_of_idcols = join(', ', sort { $a <=> $b } keys %{ $stats->{idcols_seen} } );

  my $parser_src = sprintf (<<'EOS', $list_of_idcols, $top_node_key, $top_node_key_assembler||'', $data_assemblers);
### BEGIN LITERAL STRING EVAL
  my ($rows_pos, $result_pos, $cur_row_data, %%cur_row_ids, @collapse_idx, $is_new_res) = (0,0);

  # this loop is a bit arcane - the rationale is that the passed in
  # $_[0] will either have only one row (->next) or will have all
  # rows already pulled in (->all and/or unordered). Given that the
  # result can be rather large - we reuse the same already allocated
  # array, since the collapsed prefetch is smaller by definition.
  # At the end we cut the leftovers away and move on.
  while ($cur_row_data =
    ( ( $rows_pos >= 0 and $_[0][$rows_pos++] ) or do { $rows_pos = -1; undef } )
      ||
    ($_[1] and $_[1]->())
  ) {

    # due to left joins some of the ids may be NULL/undef, and
    # won't play well when used as hash lookups
    # we also need to differentiate NULLs on per-row/per-col basis
    #(otherwise folding of optional 1:1s will be greatly confused
    $cur_row_ids{$_} = defined $cur_row_data->[$_] ? $cur_row_data->[$_] : "\0NULL\xFF$rows_pos\xFF$_\0"
      for (%1$s);

    # maybe(!) cache the top node id calculation
    %3$s

    $is_new_res = ! $collapse_idx[0]%2$s and (
      $_[1] and $result_pos and (unshift @{$_[2]}, $cur_row_data) and last
    );

    # the rel assemblers
    %4$s

    $_[0][$result_pos++] = $collapse_idx[0]%2$s
      if $is_new_res;
  }

  splice @{$_[0]}, $result_pos; # truncate the passed in array for cases of collapsing ->all()
### END LITERAL STRING EVAL
EOS

  # !!! note - different var than the one above
  # change the quoted placeholders to unquoted alias-references
  $parser_src =~ s/ \' \xFF__VALPOS__(\d+)__\xFF \' /"\$cur_row_data->[$1]"/gex;
  $parser_src =~ s/ \' \xFF__IDVALPOS__(\d+)__\xFF \' /"\$cur_row_ids{$1}"/gex;

  $parser_src;
}


# the collapsing nested structure recursor
sub __visit_infmap_collapse {
  my $args = {%{ shift() }};

  my $cur_node_idx = ${ $args->{-node_idx_counter} ||= \do { my $x = 0} }++;

  my ($my_cols, $rel_cols);
  for ( keys %{$args->{val_index}} ) {
    if ($_ =~ /^ ([^\.]+) \. (.+) /x) {
      $rel_cols->{$1}{$2} = $args->{val_index}{$_};
    }
    else {
      $my_cols->{$_} = $args->{val_index}{$_};
    }
  }

  my $node_key = $args->{collapse_map}->{-custom_node_key} || join ('', map
    { "{'\xFF__IDVALPOS__${_}__\xFF'}" }
    @{$args->{collapse_map}->{-identifying_columns}}
  );

  my $me_struct = $my_cols
    ? __visit_dump([{ map { $_ => "\xFF__VALPOS__$my_cols->{$_}__\xFF" } (keys %$my_cols) }])
    : undef
  ;
  my $node_idx_slot = sprintf '$collapse_idx[%d]%s', $cur_node_idx, $node_key;

  my $parent_attach_slot = sprintf( '$collapse_idx[%d]%s[1]{%s}',
    @{$args}{qw/-parent_node_idx -parent_node_key/},
    perlstring($args->{-node_relname}),
  ) if $args->{-node_relname};

  my @src;
  if ($cur_node_idx == 0) {
    push @src, sprintf( '%s ||= %s;',
      $node_idx_slot,
      $me_struct,
    ) if $me_struct;
  }
  elsif ($args->{collapse_map}->{-is_single}) {
    push @src, sprintf ( '%s ||= %s%s;',
      $parent_attach_slot,
      $node_idx_slot,
      $me_struct ? " ||= $me_struct" : '',
    );
  }
  else {
    push @src, sprintf('push @{%s}, %s%s unless %s;',
      $parent_attach_slot,
      $node_idx_slot,
      $me_struct ? " ||= $me_struct" : '',
      $node_idx_slot,
    );
  }

  # DISABLEPRUNE
  #my $known_defined = { %{ $parent_info->{known_defined} || {} } };
  #$known_defined->{$_}++ for @{$args->{collapse_map}->{-identifying_columns}};
  my $stats;
  for my $rel (sort keys %$rel_cols) {

#    push @src, sprintf(
#      '%s[1]{%s} ||= [];', $node_idx_slot, perlstring($rel)
#    ) unless $args->{collapse_map}->{$rel}{-is_single};

    ($src[$#src + 1], $stats->{$rel}) = __visit_infmap_collapse({ %$args,
      val_index => $rel_cols->{$rel},
      collapse_map => $args->{collapse_map}{$rel},
      -parent_node_idx => $cur_node_idx,
      -parent_node_key => $node_key,
      -node_relname => $rel,
    });

    # FIXME SUBOPTIMAL DISABLEPRUNE - disabled to satisfy t/resultset/inflate_result_api.t
    #if ($args->{collapse_map}->{$rel}{-is_optional} and my @null_checks = map
    #  { "(! defined '\xFF__IDVALPOS__${_}__\xFF')" }
    #  sort { $a <=> $b } grep
    #    { ! $known_defined->{$_} }
    #    @{$args->{collapse_map}->{$rel}{-identifying_columns}}
    #) {
    #  $src[-1] = sprintf( '(%s) or %s',
    #    join (' || ', @null_checks ),
    #    $src[-1],
    #  );
    #}
  }

  return (
    join("\n", @src),
    {
      idcols_seen => {
        ( map { %{ $_->{idcols_seen} } } values %$stats ),
        ( map { $_ => 1 } @{$args->{collapse_map}->{-identifying_columns}} ),
      }
    }
  );
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
      ->Useperl (0)
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

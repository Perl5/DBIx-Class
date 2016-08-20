package   #hide from PAUSE
  DBIx::Class::SQLMaker::Util;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw(
  normalize_sqla_condition
  extract_equality_conditions
);

use DBIx::Class::Carp;
use Carp 'croak';
use SQL::Abstract qw( is_literal_value is_plain_value );
use DBIx::Class::_Util qw( UNRESOLVABLE_CONDITION serialize dump_value );


# Attempts to flatten a passed in SQLA condition as much as possible towards
# a plain hashref, *without* altering its semantics.
#
# FIXME - while relatively robust, this is still imperfect, one of the first
# things to tackle when we get access to a formalized AST. Note that this code
# is covered by a *ridiculous* amount of tests, so starting with porting this
# code would be a rather good exercise
sub normalize_sqla_condition {
  my ($where, $where_is_anded_array) = @_;

  my $fin;

  if (! $where) {
    return;
  }
  elsif ($where_is_anded_array or ref $where eq 'HASH') {

    my @pairs;

    my @pieces = $where_is_anded_array ? @$where : $where;
    while (@pieces) {
      my $chunk = shift @pieces;

      if (ref $chunk eq 'HASH') {
        for (sort keys %$chunk) {

          # Match SQLA 1.79 behavior
          unless( length $_ ) {
            is_literal_value($chunk->{$_})
              ? carp 'Hash-pairs consisting of an empty string with a literal are deprecated, use -and => [ $literal ] instead'
              : croak 'Supplying an empty left hand side argument is not supported in hash-pairs'
            ;
          }

          push @pairs, $_ => $chunk->{$_};
        }
      }
      elsif (ref $chunk eq 'ARRAY') {
        push @pairs, -or => $chunk
          if @$chunk;
      }
      elsif ( ! length ref $chunk) {

        # Match SQLA 1.79 behavior
        croak("Supplying an empty left hand side argument is not supported in array-pairs")
          if $where_is_anded_array and (! defined $chunk or ! length $chunk);

        push @pairs, $chunk, shift @pieces;
      }
      else {
        push @pairs, '', $chunk;
      }
    }

    return unless @pairs;

    my @conds = _normalize_cond_unroll_pairs(\@pairs)
      or return;

    # Consolidate various @conds back into something more compact
    for my $c (@conds) {
      if (ref $c ne 'HASH') {
        push @{$fin->{-and}}, $c;
      }
      else {
        for my $col (sort keys %$c) {

          # consolidate all -and nodes
          if ($col =~ /^\-and$/i) {
            push @{$fin->{-and}},
              ref $c->{$col} eq 'ARRAY' ? @{$c->{$col}}
            : ref $c->{$col} eq 'HASH' ? %{$c->{$col}}
            : { $col => $c->{$col} }
            ;
          }
          elsif ($col =~ /^\-/) {
            push @{$fin->{-and}}, { $col => $c->{$col} };
          }
          elsif (exists $fin->{$col}) {
            $fin->{$col} = [ -and => map {
              (ref $_ eq 'ARRAY' and ($_->[0]||'') =~ /^\-and$/i )
                ? @{$_}[1..$#$_]
                : $_
              ;
            } ($fin->{$col}, $c->{$col}) ];
          }
          else {
            $fin->{$col} = $c->{$col};
          }
        }
      }
    }
  }
  elsif (ref $where eq 'ARRAY') {
    # we are always at top-level here, it is safe to dump empty *standalone* pieces
    my $fin_idx;

    for (my $i = 0; $i <= $#$where; $i++ ) {

      # Match SQLA 1.79 behavior
      croak(
        "Supplying an empty left hand side argument is not supported in array-pairs"
      ) if (! defined $where->[$i] or ! length $where->[$i]);

      my $logic_mod = lc ( ($where->[$i] =~ /^(\-(?:and|or))$/i)[0] || '' );

      if ($logic_mod) {
        $i++;
        croak("Unsupported top-level op/arg pair: [ $logic_mod => $where->[$i] ]")
          unless ref $where->[$i] eq 'HASH' or ref $where->[$i] eq 'ARRAY';

        my $sub_elt = normalize_sqla_condition({ $logic_mod => $where->[$i] })
          or next;

        my @keys = keys %$sub_elt;
        if ( @keys == 1 and $keys[0] !~ /^\-/ ) {
          $fin_idx->{ "COL_$keys[0]_" . serialize $sub_elt } = $sub_elt;
        }
        else {
          $fin_idx->{ "SER_" . serialize $sub_elt } = $sub_elt;
        }
      }
      elsif (! length ref $where->[$i] ) {
        my $sub_elt = normalize_sqla_condition({ @{$where}[$i, $i+1] })
          or next;

        $fin_idx->{ "COL_$where->[$i]_" . serialize $sub_elt } = $sub_elt;
        $i++;
      }
      else {
        $fin_idx->{ "SER_" . serialize $where->[$i] } = normalize_sqla_condition( $where->[$i] ) || next;
      }
    }

    if (! $fin_idx) {
      return;
    }
    elsif ( keys %$fin_idx == 1 ) {
      $fin = (values %$fin_idx)[0];
    }
    else {
      my @or;

      # at this point everything is at most one level deep - unroll if needed
      for (sort keys %$fin_idx) {
        if ( ref $fin_idx->{$_} eq 'HASH' and keys %{$fin_idx->{$_}} == 1 ) {
          my ($l, $r) = %{$fin_idx->{$_}};

          if (
            ref $r eq 'ARRAY'
              and
            (
              ( @$r == 1 and $l =~ /^\-and$/i )
                or
              $l =~ /^\-or$/i
            )
          ) {
            push @or, @$r
          }

          elsif (
            ref $r eq 'HASH'
              and
            keys %$r == 1
              and
            $l =~ /^\-(?:and|or)$/i
          ) {
            push @or, %$r;
          }

          else {
            push @or, $l, $r;
          }
        }
        else {
          push @or, $fin_idx->{$_};
        }
      }

      $fin->{-or} = \@or;
    }
  }
  else {
    # not a hash not an array
    $fin = { -and => [ $where ] };
  }

  # unroll single-element -and's
  while (
    $fin->{-and}
      and
    @{$fin->{-and}} < 2
  ) {
    my $and = delete $fin->{-and};
    last if @$and == 0;

    # at this point we have @$and == 1
    if (
      ref $and->[0] eq 'HASH'
        and
      ! grep { exists $fin->{$_} } keys %{$and->[0]}
    ) {
      $fin = {
        %$fin, %{$and->[0]}
      };
    }
    else {
      $fin->{-and} = $and;
      last;
    }
  }

  # compress same-column conds found in $fin
  for my $col ( grep { $_ !~ /^\-/ } keys %$fin ) {
    next unless ref $fin->{$col} eq 'ARRAY' and ($fin->{$col}[0]||'') =~ /^\-and$/i;
    my $val_bag = { map {
      (! defined $_ )                          ? ( UNDEF => undef )
    : ( ! length ref $_ or is_plain_value $_ ) ? ( "VAL_$_" => $_ )
    : ( ( 'SER_' . serialize $_ ) => $_ )
    } @{$fin->{$col}}[1 .. $#{$fin->{$col}}] };

    if (keys %$val_bag == 1 ) {
      ($fin->{$col}) = values %$val_bag;
    }
    else {
      $fin->{$col} = [ -and => map { $val_bag->{$_} } sort keys %$val_bag ];
    }
  }

  return keys %$fin ? $fin : ();
}

sub _normalize_cond_unroll_pairs {
  my $pairs = shift;

  my @conds;

  while (@$pairs) {
    my ($lhs, $rhs) = splice @$pairs, 0, 2;

    if (! length $lhs) {
      push @conds, normalize_sqla_condition($rhs);
    }
    elsif ( $lhs =~ /^\-and$/i ) {
      push @conds, normalize_sqla_condition($rhs, (ref $rhs eq 'ARRAY'));
    }
    elsif ( $lhs =~ /^\-or$/i ) {
      push @conds, normalize_sqla_condition(
        (ref $rhs eq 'HASH') ? [ map { $_ => $rhs->{$_} } sort keys %$rhs ] : $rhs
      );
    }
    else {
      if (ref $rhs eq 'HASH' and ! keys %$rhs) {
        # FIXME - SQLA seems to be doing... nothing...?
      }
      # normalize top level -ident, for saner extract_fixed_condition_columns code
      elsif (ref $rhs eq 'HASH' and keys %$rhs == 1 and exists $rhs->{-ident}) {
        push @conds, { $lhs => { '=', $rhs } };
      }
      elsif (ref $rhs eq 'HASH' and keys %$rhs == 1 and exists $rhs->{-value} and is_plain_value $rhs->{-value}) {
        push @conds, { $lhs => $rhs->{-value} };
      }
      elsif (ref $rhs eq 'HASH' and keys %$rhs == 1 and exists $rhs->{'='}) {
        if ( length ref $rhs->{'='} and is_literal_value $rhs->{'='} ) {
          push @conds, { $lhs => $rhs };
        }
        else {
          for my $p (_normalize_cond_unroll_pairs([ $lhs => $rhs->{'='} ])) {

            # extra sanity check
            if (keys %$p > 1) {
              local $Data::Dumper::Deepcopy = 1;
              croak(
                "Internal error: unexpected collapse unroll:"
              . dump_value { in => { $lhs => $rhs }, out => $p }
              );
            }

            my ($l, $r) = %$p;

            push @conds, (
              ! length ref $r
                or
              # the unroller recursion may return a '=' prepended value already
              ref $r eq 'HASH' and keys %$rhs == 1 and exists $rhs->{'='}
                or
              is_plain_value($r)
            )
              ? { $l => $r }
              : { $l => { '=' => $r } }
            ;
          }
        }
      }
      elsif (ref $rhs eq 'ARRAY') {
        # some of these conditionals encounter multi-values - roll them out using
        # an unshift, which will cause extra looping in the while{} above
        if (! @$rhs ) {
          push @conds, { $lhs => [] };
        }
        elsif ( ($rhs->[0]||'') =~ /^\-(?:and|or)$/i ) {
          croak("Value modifier not followed by any values: $lhs => [ $rhs->[0] ] ")
            if @$rhs == 1;

          if( $rhs->[0] =~ /^\-and$/i ) {
            unshift @$pairs, map { $lhs => $_ } @{$rhs}[1..$#$rhs];
          }
          # if not an AND then it's an OR
          elsif(@$rhs == 2) {
            unshift @$pairs, $lhs => $rhs->[1];
          }
          else {
            push @conds, { $lhs => [ @{$rhs}[1..$#$rhs] ] };
          }
        }
        elsif (@$rhs == 1) {
          unshift @$pairs, $lhs => $rhs->[0];
        }
        else {
          push @conds, { $lhs => $rhs };
        }
      }
      # unroll func + { -value => ... }
      elsif (
        ref $rhs eq 'HASH'
          and
        ( my ($subop) = keys %$rhs ) == 1
          and
        length ref ((values %$rhs)[0])
          and
        my $vref = is_plain_value( (values %$rhs)[0] )
      ) {
        push @conds, (
          (length ref $$vref)
            ? { $lhs => $rhs }
            : { $lhs => { $subop => $$vref } }
        );
      }
      else {
        push @conds, { $lhs => $rhs };
      }
    }
  }

  return @conds;
}

# Analyzes a given condition and attempts to extract all columns
# with a definitive fixed-condition criteria. Returns a hashref
# of k/v pairs suitable to be passed to set_columns(), with a
# MAJOR CAVEAT - multi-value (contradictory) equalities are still
# represented as a reference to the UNRESOVABLE_CONDITION constant
# The reason we do this is that some codepaths only care about the
# codition being stable, as opposed to actually making sense
#
# The normal mode is used to figure out if a resultset is constrained
# to a column which is part of a unique constraint, which in turn
# allows us to better predict how ordering will behave etc.
#
# With the optional "consider_nulls" boolean argument, the function
# is instead used to infer inambiguous values from conditions
# (e.g. the inheritance of resultset conditions on new_result)
#
sub extract_equality_conditions {
  my ($where, $consider_nulls) = @_;
  my $where_hash = normalize_sqla_condition($where);

  my $res = {};
  my ($c, $v);
  for $c (keys %$where_hash) {
    my $vals;

    if (!defined ($v = $where_hash->{$c}) ) {
      $vals->{UNDEF} = $v if $consider_nulls
    }
    elsif (
      ref $v eq 'HASH'
        and
      keys %$v == 1
    ) {
      if (exists $v->{-value}) {
        if (defined $v->{-value}) {
          $vals->{"VAL_$v->{-value}"} = $v->{-value}
        }
        elsif( $consider_nulls ) {
          $vals->{UNDEF} = $v->{-value};
        }
      }
      # do not need to check for plain values - normalize_sqla_condition did it for us
      elsif(
        length ref $v->{'='}
          and
        (
          ( ref $v->{'='} eq 'HASH' and keys %{$v->{'='}} == 1 and exists $v->{'='}{-ident} )
            or
          is_literal_value($v->{'='})
        )
       ) {
        $vals->{ 'SER_' . serialize $v->{'='} } = $v->{'='};
      }
    }
    elsif (
      ! length ref $v
        or
      is_plain_value ($v)
    ) {
      $vals->{"VAL_$v"} = $v;
    }
    elsif (ref $v eq 'ARRAY' and ($v->[0]||'') eq '-and') {
      for ( @{$v}[1..$#$v] ) {
        my $subval = extract_equality_conditions({ $c => $_ }, 'consider nulls');  # always fish nulls out on recursion
        next unless exists $subval->{$c};  # didn't find anything
        $vals->{
          ! defined $subval->{$c}                                        ? 'UNDEF'
        : ( ! length ref $subval->{$c} or is_plain_value $subval->{$c} ) ? "VAL_$subval->{$c}"
        : ( 'SER_' . serialize $subval->{$c} )
        } = $subval->{$c};
      }
    }

    if (keys %$vals == 1) {
      ($res->{$c}) = (values %$vals)
        unless !$consider_nulls and exists $vals->{UNDEF};
    }
    elsif (keys %$vals > 1) {
      $res->{$c} = UNRESOLVABLE_CONDITION;
    }
  }

  $res;
}

1;

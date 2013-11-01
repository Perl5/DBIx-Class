package DBIx::Class::SQLMaker::Converter;

use Data::Query::Constants qw(DQ_ALIAS DQ_GROUP DQ_WHERE DQ_JOIN DQ_SLICE);
use Moo;
use namespace::clean;

extends 'SQL::Abstract::Converter';

has limit_dialect => (is => 'ro', required => 1);
has name_sep => (is => 'ro', required => 1);
has slice_stability => (is => 'ro', required => 1);
has slice_subquery => (is => 'ro', required => 1);

sub __max_int () { 0x7FFFFFFF }

# Handle limit-dialect selection
sub _select_attrs {
  my ($self, $table, $fields, $where, $rs_attrs, $limit, $offset) = @_;

  if (defined $offset) {
    die('A supplied offset must be a non-negative integer')
      if ( $offset =~ /\D/ or $offset < 0 );
  }
  $offset ||= 0;

  if (defined $limit) {
    die('A supplied limit must be a positive integer')
      if ( $limit =~ /\D/ or $limit <= 0 );
  }
  elsif ($offset) {
    $limit = $self->__max_int;
  }

  my %final_attrs = (%{$rs_attrs||{}}, limit => $limit, offset => $offset);

  if ($limit or $offset) {
    my %slice_stability = %{$self->slice_stability};

    if (my $stability = $slice_stability{$offset ? 'offset' : 'limit'}) {
      my $source = $rs_attrs->{_rsroot_rsrc};
      unless (
        $final_attrs{order_is_stable}
        = $final_attrs{preserve_order}
        = $source->schema->storage
                 ->_order_by_is_stable(
                     @final_attrs{qw(from order_by where)}
                   )
      ) {
        if ($stability eq 'requires') {
          if ($self->_order_by_to_dq($final_attrs{order_by})) {
            die(
                $self->limit_dialect.' limit/offset implementation requires a stable order for '.($offset ? 'offset' : 'limit')
            );
          }
          if (my $ident_cols = $source->_identifying_column_set) {
            $final_attrs{order_by} = [
                map "$final_attrs{alias}.$_", @$ident_cols
            ];
            $final_attrs{order_is_stable} = 1;
          } else {
            die(sprintf(
              'Unable to auto-construct stable order criteria for "skimming type" 
  limit '
              . "dialect based on source '%s'", $source->name) );
          }
        }
      }

    }

    my %slice_subquery = %{$self->slice_subquery};

    if (my $subquery = $slice_subquery{$offset ? 'offset' : 'limit'}) {
      $fields = [ map {
        my $f = $fields->[$_];
        if (ref $f) {
          $f = { '' => $f } unless ref($f) eq 'HASH';
          ($f->{-as} ||= $final_attrs{as}[$_]) =~ s/\Q${\$self->name_sep}/__/g;
        } elsif ($f !~ /^\Q$final_attrs{alias}${\$self->name_sep}/) {
          $f = { '' => $f };
          ($f->{-as} ||= $final_attrs{as}[$_]) =~ s/\Q${\$self->name_sep}/__/g;
        }
        $f;
        } 0 .. $#$fields ];
    }
  }

  return ($fields, \%final_attrs);
}

around _select_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my ($table, undef, $where) = @_;
  my ($fields, $attrs) = $self->_select_attrs(@_);
  my $orig_dq = $self->$orig($table, $fields, $where, $attrs->{order_by}, $attrs);
  return $orig_dq unless $attrs->{limit};
  +{
    type => DQ_SLICE,
    from => $orig_dq,
    limit => do {
      local $SQL::Abstract::Converter::Cur_Col_Meta
        = { sqlt_datatype => 'integer' };
      $self->_value_to_dq($attrs->{limit})
    },
    ($attrs->{offset}
      ? (offset => do {
          local $SQL::Abstract::Converter::Cur_Col_Meta
            = { sqlt_datatype => 'integer' };
          $self->_value_to_dq($attrs->{offset})
        })
      : ()
    ),
    ($attrs->{order_is_stable}
      ? (order_is_stable => 1)
      : ()),
    ($attrs->{preserve_order}
      ? (preserve_order => 1)
      : ())
  };
};

around _select_field_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my ($field) = @_;
  my $ref = ref $field;
  if ($ref eq 'HASH') {
    my %hash = %$field;  # shallow copy

    my $as = delete $hash{-as};   # if supplied

    my ($func, $args, @toomany) = %hash;

    # there should be only one pair
    if (@toomany) {
      die( "Malformed select argument - too many keys in hash: " . join (',', keys %$field ) );
    }

    if (lc ($func) eq 'distinct' && ref $args eq 'ARRAY' && @$args > 1) {
      die(
        'The select => { distinct => ... } syntax is not supported for multiple columns.'
       .' Instead please use { group_by => [ qw/' . (join ' ', @$args) . '/ ] }'
       .' or { select => [ qw/' . (join ' ', @$args) . '/ ], distinct => 1 }'
      );
    }

    my $field_dq = do {
      if ($func) {
        $self->_op_to_dq(
          apply => $self->_ident_to_dq(uc($func)),
          @{$self->_select_field_list_to_dq($args)},
        );
      } else {
        $self->_select_field_to_dq($args);
      }
    };

    return $field_dq unless $as;

    return +{
      type => DQ_ALIAS,
      from => $field_dq,
      to => $as
    };
  } else {
    return $self->$orig(@_);
  }
};

around _source_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my $attrs = $_[4]; # table, fields, where, order, attrs
  my $start_dq = $self->$orig(@_);
  # if we have HAVING but no GROUP BY we render an empty DQ_GROUP
  # node, which causes DQ to recognise the HAVING as being what it is.
  # This ... is kinda bull. But that's how HAVING is specified.
  return $start_dq unless $attrs->{group_by} or $attrs->{having};
  my $grouped_dq = $self->_group_by_to_dq($attrs->{group_by}||[], $start_dq);
  return $grouped_dq unless $attrs->{having};
  +{
    type => DQ_WHERE,
    from => $grouped_dq,
    where => $self->_where_to_dq($attrs->{having})
  };
};

sub _group_by_to_dq {
  my ($self, $group, $from) = @_;
  +{
    type => DQ_GROUP,
    by => $self->_select_field_list_to_dq($group),
    from => $from,
  };
}

around _table_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my ($spec) = @_;
  if (my $ref = ref $spec ) {
    if ($ref eq 'ARRAY') {
      return $self->_join_to_dq(@$spec);
    }
    elsif ($ref eq 'HASH') {
      my ($as, $table, $toomuch) = ( map
        { $_ => $spec->{$_} }
        ( grep { $_ !~ /^\-/ } keys %$spec )
      );
      die "Only one table/as pair expected in from-spec but an exra '$toomuch' key present"
        if defined $toomuch;

      return +{
        type => DQ_ALIAS,
        from => $self->_table_to_dq($table),
        to => $as,
        ($spec->{-rsrc}
          ? (
              'dbix-class.source_name' => $spec->{-rsrc}->source_name,
              'dbix-class.join_path' => $spec->{-join_path},
              'dbix-class.is_single' => $spec->{-is_single},
            )
          : ()
        )
      };
    }
  }
  return $self->$orig(@_);
};

sub _join_to_dq {
  my ($self, $from, @joins) = @_;

  my $cur_dq = $self->_table_to_dq($from);

  if (!@joins or @joins == 1 and ref($joins[0]) eq 'HASH') {
    return $cur_dq;
  }

  foreach my $join (@joins) {
    my ($to, $on) = @$join;

    # check whether a join type exists
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    my $join_type;
    if (ref($to_jt) eq 'HASH' and defined($to_jt->{-join_type})) {
      $join_type = lc($to_jt->{-join_type});
      $join_type =~ s/^\s+ | \s+$//xg;
      undef($join_type) unless $join_type =~ s/^(left|right).*/$1/;
    }

    $cur_dq = +{
      type => DQ_JOIN,
      ($join_type ? (outer => $join_type) : ()),
      left => $cur_dq,
      right => $self->_table_to_dq($to),
      ($on
        ? (on => $self->_expr_to_dq($self->_expand_join_condition($on)))
        : ()),
    };
  }

  return $cur_dq;
}

sub _expand_join_condition {
  my ($self, $cond) = @_;

  # Backcompat for the old days when a plain hashref
  # { 't1.col1' => 't2.col2' } meant ON t1.col1 = t2.col2
  # Once things settle we should start warning here so that
  # folks unroll their hacks
  if (
    ref $cond eq 'HASH'
      and
    keys %$cond == 1
      and
    (keys %$cond)[0] =~ /\./
      and
    ! ref ( (values %$cond)[0] )
  ) {
    return +{ keys %$cond => { -ident => values %$cond } }
  }
  elsif ( ref $cond eq 'ARRAY' ) {
    return [ map $self->_expand_join_condition($_), @$cond ];
  }

  return $cond;
}

around _bind_to_dq => sub {
  my ($orig, $self) = (shift, shift);
  my @args = do {
    if ($self->bind_meta) {
      map { ref($_) eq 'ARRAY' ? $_ : [ {} => $_ ] } @_
    } else {
      @_
    }
  };
  return $self->$orig(@args);
};

1;

=head1 OPERATORS

=head2 -ident

Used to explicitly specify an SQL identifier. Takes a plain string as value
which is then invariably treated as a column name (and is being properly
quoted if quoting has been requested). Most useful for comparison of two
columns:

    my %where = (
        priority => { '<', 2 },
        requestor => { -ident => 'submitter' }
    );

which results in:

    $stmt = 'WHERE "priority" < ? AND "requestor" = "submitter"';
    @bind = ('2');

=head2 -value

The -value operator signals that the argument to the right is a raw bind value.
It will be passed straight to DBI, without invoking any of the SQL::Abstract
condition-parsing logic. This allows you to, for example, pass an array as a
column value for databases that support array datatypes, e.g.:

    my %where = (
        array => { -value => [1, 2, 3] }
    );

which results in:

    $stmt = 'WHERE array = ?';
    @bind = ([1, 2, 3]);

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

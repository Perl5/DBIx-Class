package DBIx::Class::SQLMaker;

=head1 NAME

DBIx::Class::SQLMaker - An SQL::Abstract-based SQL maker class

=head1 DESCRIPTION

This module is a subclass of L<SQL::Abstract> and includes a number of
DBIC-specific workarounds, not yet suitable for inclusion into the
L<SQL::Abstract> core. It also provides all (and more than) the functionality
of L<SQL::Abstract::Limit>, see L<DBIx::Class::SQLMaker::LimitDialects> for
more info.

Currently the enhancements to L<SQL::Abstract> are:

=over

=item * Support for C<JOIN> statements (via extended C<table/from> support)

=item * Support of functions in C<SELECT> lists

=item * C<GROUP BY>/C<HAVING> support (via extensions to the order_by parameter)

=item * Support of C<...FOR UPDATE> type of select statement modifiers

=item * The -ident operator

=item * The -value operator

=back

=cut

use base qw/
  DBIx::Class::SQLMaker::LimitDialects
  SQL::Abstract
  Class::Accessor::Grouped
/;
use mro 'c3';
use strict;
use warnings;
use Sub::Name 'subname';
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract|^Try::Tiny/;
use namespace::clean;

__PACKAGE__->mk_group_accessors (simple => qw/quote_char name_sep limit_dialect/);

# for when I need a normalized l/r pair
sub _quote_chars {
  map
    { defined $_ ? $_ : '' }
    ( ref $_[0]->{quote_char} ? (@{$_[0]->{quote_char}}) : ( ($_[0]->{quote_char}) x 2 ) )
  ;
}

BEGIN {
  # reinstall the carp()/croak() functions imported into SQL::Abstract
  # as Carp and Carp::Clan do not like each other much
  no warnings qw/redefine/;
  no strict qw/refs/;
  for my $f (qw/carp croak/) {

    my $orig = \&{"SQL::Abstract::$f"};
    my $clan_import = \&{$f};
    *{"SQL::Abstract::$f"} = subname "SQL::Abstract::$f" =>
      sub {
        if (Carp::longmess() =~ /DBIx::Class::SQLMaker::[\w]+ .+? called \s at/x) {
          goto $clan_import;
        }
        else {
          goto $orig;
        }
      };
  }
}

# the "oh noes offset/top without limit" constant
# limited to 32 bits for sanity (and consistency,
# since it is ultimately handed to sprintf %u)
# Implemented as a method, since ::Storage::DBI also
# refers to it (i.e. for the case of software_limit or
# as the value to abuse with MSSQL ordered subqueries)
sub __max_int { 0xFFFFFFFF };

sub new {
  my $self = shift->next::method(@_);

  # use the same coderefs, they are prepared to handle both cases
  my @extra_dbic_syntax = (
    { regex => qr/^ ident $/xi, handler => '_where_op_IDENT' },
    { regex => qr/^ value $/xi, handler => '_where_op_VALUE' },
  );

  push @{$self->{special_ops}}, @extra_dbic_syntax;
  push @{$self->{unary_ops}}, @extra_dbic_syntax;

  $self;
}

sub _where_op_IDENT {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;
  if (ref $rhs) {
    croak "-$op takes a single scalar argument (a quotable identifier)";
  }

  # in case we are called as a top level special op (no '=')
  my $lhs = shift;

  $_ = $self->_convert($self->_quote($_)) for ($lhs, $rhs);

  return $lhs
    ? "$lhs = $rhs"
    : $rhs
  ;
}

sub _where_op_VALUE {
  my $self = shift;
  my ($op, $rhs) = splice @_, -2;

  # in case we are called as a top level special op (no '=')
  my $lhs = shift;

  my @bind = [
    ($lhs || $self->{_nested_func_lhs} || croak "Unable to find bindtype for -value $rhs"),
    $rhs
  ];

  return $lhs
    ? (
      $self->_convert($self->_quote($lhs)) . ' = ' . $self->_convert('?'),
      @bind
    )
    : (
      $self->_convert('?'),
      @bind,
    )
  ;
}

# Handle limit-dialect selection
sub select {
  my ($self, $table, $fields, $where, $rs_attrs, $limit, $offset) = @_;


  $fields = $self->_recurse_fields($fields);

  if (defined $offset) {
    croak ('A supplied offset must be a non-negative integer')
      if ( $offset =~ /\D/ or $offset < 0 );
  }
  $offset ||= 0;

  if (defined $limit) {
    croak ('A supplied limit must be a positive integer')
      if ( $limit =~ /\D/ or $limit <= 0 );
  }
  elsif ($offset) {
    $limit = $self->__max_int;
  }


  my ($sql, @bind);
  if ($limit) {
    # this is legacy code-flow from SQLA::Limit, it is not set in stone

    ($sql, @bind) = $self->next::method ($table, $fields, $where);

    my $limiter =
      $self->can ('emulate_limit')  # also backcompat hook from SQLA::Limit
        ||
      do {
        my $dialect = $self->limit_dialect
          or croak "Unable to generate SQL-limit - no limit dialect specified on $self, and no emulate_limit method found";
        $self->can ("_$dialect")
          or croak (__PACKAGE__ . " does not implement the requested dialect '$dialect'");
      }
    ;

    $sql = $self->$limiter ($sql, $rs_attrs, $limit, $offset);
  }
  else {
    ($sql, @bind) = $self->next::method ($table, $fields, $where, $rs_attrs);
  }

  push @{$self->{where_bind}}, @bind;

# this *must* be called, otherwise extra binds will remain in the sql-maker
  my @all_bind = $self->_assemble_binds;

  $sql .= $self->_lock_select ($rs_attrs->{for})
    if $rs_attrs->{for};

  return wantarray ? ($sql, @all_bind) : $sql;
}

sub _assemble_binds {
  my $self = shift;
  return map { @{ (delete $self->{"${_}_bind"}) || [] } } (qw/from where having order/);
}

my $for_syntax = {
  update => 'FOR UPDATE',
  shared => 'FOR SHARE',
};
sub _lock_select {
  my ($self, $type) = @_;
  my $sql = $for_syntax->{$type} || croak "Unknown SELECT .. FOR type '$type' requested";
  return " $sql";
}

# Handle default inserts
sub insert {
# optimized due to hotttnesss
#  my ($self, $table, $data, $options) = @_;

  # SQLA will emit INSERT INTO $table ( ) VALUES ( )
  # which is sadly understood only by MySQL. Change default behavior here,
  # until SQLA2 comes with proper dialect support
  if (! $_[2] or (ref $_[2] eq 'HASH' and !keys %{$_[2]} ) ) {
    my @bind;
    my $sql = sprintf(
      'INSERT INTO %s DEFAULT VALUES', $_[0]->_quote($_[1])
    );

    if ( ($_[3]||{})->{returning} ) {
      my $s;
      ($s, @bind) = $_[0]->_insert_returning ($_[3]);
      $sql .= $s;
    }

    return ($sql, @bind);
  }

  next::method(@_);
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

  if (my $g = $self->_recurse_fields($arg->{group_by}) ) {
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

  return $sql;
}

sub _order_by {
  my ($self, $arg) = @_;

  # check that we are not called in legacy mode (order_by as 4th argument)
  if (ref $arg eq 'HASH' and not grep { $_ =~ /^-(?:desc|asc)/i } keys %$arg ) {
    return $self->_parse_rs_attrs ($arg);
  }
  else {
    my ($sql, @bind) = $self->next::method($arg);
    push @{$self->{order_bind}}, @bind;
    return $sql;
  }
}

sub _table {
# optimized due to hotttnesss
#  my ($self, $from) = @_;
  if (my $ref = ref $_[1] ) {
    if ($ref eq 'ARRAY') {
      return $_[0]->_recurse_from(@{$_[1]});
    }
    elsif ($ref eq 'HASH') {
      return $_[0]->_make_as($_[1]);
    }
  }

  return $_[0]->next::method ($_[1]);
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
    croak "Can't handle this yet!";
  }
}

1;

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

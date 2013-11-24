package DBIx::Class::ResultSet::Role::DQMethods;

use Data::Query::ExprHelpers;
use Safe::Isa;
use Moo::Role;

sub _dq_converter {
  shift->result_source->schema->storage->sql_maker->converter;
}

sub where {
  my ($self, $where) = @_;
  if ($where->$_isa('Data::Query::ExprBuilder')) {
    return $self->_apply_dq_where($where->{expr});
  } elsif (ref($where) eq 'HASH') {
    return $self->_apply_dq_where(
             $self->_dq_converter->_where_to_dq($where)
           );
  }
  die "Argument to ->where must be ExprBuilder or SQL::Abstract hashref, got: "
      .(defined($where) ? $where : 'undef');
}

sub _apply_dq_where {
  my ($self, $expr) = @_;
  my ($mapped, $need_join) = $self->_remap_identifiers($expr);
  $self->search_rs(\$mapped, { join => $need_join });
}

sub _remap_identifiers {
  my ($self, $dq) = @_;
  my $map = {
    '' => {
      -alias => $self->current_source_alias,
      -rsrc => $self->result_source,
    }
  };
  my $attrs = $self->_resolved_attrs;
  foreach my $j ( @{$attrs->{from}}[1 .. $#{$attrs->{from}} ] ) {
    next unless $j->[0]{-alias};
    next unless $j->[0]{-join_path};
    my $p = $map;
    $p = $p->{$_} ||= {} for map { keys %$_ } @{$j->[0]{-join_path}};
    $p->{''} = $j->[0];
  }

  my $seen_join = { %{$attrs->{seen_join}||{}} };
  my $storage = $self->result_source->storage;
  my @need_join;
  my $mapped = map_dq_tree {
    return $_ unless is_Identifier;
    my @el = @{$_->{elements}};
    my $last = pop @el;
    my $p = $map;
    $p = $p->{$_} ||= {} for @el;
    if (my $alias = $p->{''}{'-alias'}) {
      return Identifier($alias, $last);
    }
    my $need = my $j = {};
    $j = $j->{$_} = {} for @el;
    push @need_join, $need;
    my $alias = $storage->relname_to_table_alias(
      $el[-1], ++$seen_join->{$el[-1]}
    );
    return Identifier($alias, $last);
  } $dq;
  return ($mapped, \@need_join);
}

1;

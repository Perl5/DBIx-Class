package DBIx::Class::ResultSet::Role::DQMethods;

use Data::Query::ExprHelpers;
use Safe::Isa;
use Moo::Role;
use namespace::clean;

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
  $self->search_rs(\$mapped, (@$need_join ? { join => $need_join } : ()));
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
  my %seen_op;
  my $mapped = map_dq_tree {
    return $_ unless is_Identifier;
    my @el = @{$_->{elements}};
    my $last = pop @el;
    my $p = $map;
    $p = $p->{$_} ||= {} for @el;
    unless ($p->{''}) {
      my $need = my $j = {};
      $j = $j->{$_} = {} for @el;
      my $rsrc = $map->{''}{-rsrc};
      $rsrc = $rsrc->related_source($_) for @el;
      push @need_join, $need;
      my $alias = $storage->relname_to_table_alias(
        $el[-1], ++$seen_join->{$el[-1]}
      );
      $p->{''} = { -alias => $alias, -rsrc => $rsrc };
    }
    my $info = $p->{''};
    if ($info->{-rsrc}->has_relationship($last)) {
      die "Invalid name on ".(join(',',@el)||'me').": $last is a relationship";
    }
    my $col_map = $info->{-column_mapping} ||= do {
      my $colinfo = $info->{-rsrc}->columns_info;
      +{ map +(($colinfo->{$_}{rename_for_dq}||$_) => $_), keys %$colinfo }
    };
    die "Invalid name on ".(join(',',@el)||'me').": $last"
      unless $col_map->{$last};
    return Identifier($info->{-alias}, $col_map->{$last});
  } $dq;
  return ($mapped, \@need_join);
}

1;

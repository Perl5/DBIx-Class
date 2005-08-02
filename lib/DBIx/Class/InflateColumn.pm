package DBIx::Class::InflateColumn;

use strict;
use warnings;

sub inflate_column {
  my ($self, $col, $attrs) = @_;
  die "No such column $col to inflate" unless exists $self->_columns->{$col};
  die "inflate_column needs attr hashref" unless ref $attrs eq 'HASH';
  $self->_columns->{$col}{_inflate_info} = $attrs;
  $self->mk_group_accessors('inflated_column' => $col);
  return 1;
}

sub _inflate_column_value {
  my ($self, $col, $value) = @_;
  return $value unless exists $self->_columns->{$col}{_inflate_info}{inflate};
  my $inflate = $self->_columns->{$col}{_inflate_info}{inflate};
  return $inflate->($value, $self);
}

sub _deflate_column_value {
  my ($self, $col, $value) = @_;
  return $value unless ref $value; # If it's not an object, don't touch it
  return $value unless exists $self->_columns->{$col}{_inflate_info}{deflate};
  my $deflate = $self->_columns->{$col}{_inflate_info}{deflate};
  return $deflate->($value, $self);
}

sub get_inflated_column {
  my ($self, $col) = @_;
  $self->throw("$col is not an inflated column") unless
    exists $self->_columns->{$col}{_inflate_info};
  #warn $rel;
  #warn join(', ', %{$self->{_column_data}});
  return $self->{_inflated_column}{$col}
    if exists $self->{_inflated_column}{$col};
  #my ($pri) = (keys %{$self->_relationships->{$rel}{class}->_primaries})[0];
  return $self->{_inflated_column}{$col} =
           $self->_inflate_column_value($col, $self->get_column($col));
}

sub set_inflated_column {
  my ($self, $col, @rest) = @_;
  my $ret = $self->store_inflated_column($col, @rest);
  $self->{_dirty_columns}{$col} = 1;
  return $ret;
}

sub store_inflated_column {
  my ($self, $col, $obj) = @_;
  unless (ref $obj) {
    delete $self->{_inflated_column}{$col};
    return $self->store_column($col, $obj);
  }
  $self->{_inflated_column}{$col} = $obj;
  #warn "Storing $obj: ".($obj->_ident_values)[0];
  $self->store_column($col, $self->_deflate_column_value($col, $obj));
  return $obj;
}

sub new {
  my ($class, $attrs, @rest) = @_;
  $attrs ||= {};
  my %deflated;
  foreach my $key (keys %$attrs) {
    if (exists $class->_columns->{$key}{_inflate_info}) {
      $deflated{$key} = $class->_deflate_column_value($key,
                                                        delete $attrs->{$key});
    }
  }
  return $class->NEXT::ACTUAL::new({ %$attrs, %deflated }, @rest);
}

sub _cond_value {
  my ($self, $attrs, $key, $value) = @_;
  if (exists $self->_columns->{$key}) {
    $value = $self->_deflate_column_value($key, $value);
  }
  return $self->NEXT::ACTUAL::_cond_value($attrs, $key, $value);
}

1;

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

sub _inflated_column {
  my ($self, $col, $value) = @_;
  return $value unless defined $value; # NULL is NULL is NULL
  return $value unless exists $self->_columns->{$col}{_inflate_info};
  return $value unless exists $self->_columns->{$col}{_inflate_info}{inflate};
  my $inflate = $self->_columns->{$col}{_inflate_info}{inflate};
  return $inflate->($value, $self);
}

sub _deflated_column {
  my ($self, $col, $value) = @_;
  return $value unless ref $value; # If it's not an object, don't touch it
  return $value unless exists $self->_columns->{$col}{_inflate_info};
  return $value unless exists $self->_columns->{$col}{_inflate_info}{deflate};
  my $deflate = $self->_columns->{$col}{_inflate_info}{deflate};
  return $deflate->($value, $self);
}

sub get_inflated_column {
  my ($self, $col) = @_;
  $self->throw("$col is not an inflated column") unless
    exists $self->_columns->{$col}{_inflate_info};

  return $self->{_inflated_column}{$col}
    if exists $self->{_inflated_column}{$col};
  return $self->{_inflated_column}{$col} =
           $self->_inflated_column($col, $self->get_column($col));
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

  my $deflated = $self->_deflated_column($col, $obj);
           # Do this now so we don't store if it's invalid

  $self->{_inflated_column}{$col} = $obj;
  #warn "Storing $obj: ".($obj->_ident_values)[0];
  $self->store_column($col, $deflated);
  return $obj;
}

sub new {
  my ($class, $attrs, @rest) = @_;
  $attrs ||= {};
  foreach my $key (keys %$attrs) {
    if (ref $attrs->{$key} && exists $class->_columns->{$key}{_inflate_info}) {
      $attrs->{$key} = $class->_deflated_column($key, $attrs->{$key});
    }
  }
  return $class->NEXT::ACTUAL::new($attrs, @rest);
}

1;

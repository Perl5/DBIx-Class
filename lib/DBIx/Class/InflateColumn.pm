package DBIx::Class::InflateColumn;

use strict;
use warnings;

sub inflate_column {
  my ($self, $col, $attrs) = @_;
  die "No such column $col to inflate" unless $self->has_column($col);
  die "inflate_column needs attr hashref" unless ref $attrs eq 'HASH';
  $self->column_info($col)->{_inflate_info} = $attrs;
  $self->mk_group_accessors('inflated_column' => $col);
  return 1;
}

sub _inflated_column {
  my ($self, $col, $value) = @_;
  return $value unless defined $value; # NULL is NULL is NULL
  my $info = $self->column_info($col) || die "No column info for $col";
  return $value unless exists $info->{_inflate_info};
  my $inflate = $info->{_inflate_info}{inflate};
  die "No inflator for $col" unless defined $inflate;
  return $inflate->($value, $self);
}

sub _deflated_column {
  my ($self, $col, $value) = @_;
  return $value unless ref $value; # If it's not an object, don't touch it
  my $info = $self->column_info($col) || die "No column info for $col";
  return $value unless exists $info->{_inflate_info};
  my $deflate = $info->{_inflate_info}{deflate};
  die "No deflator for $col" unless defined $deflate;
  return $deflate->($value, $self);
}

sub get_inflated_column {
  my ($self, $col) = @_;
  $self->throw("$col is not an inflated column") unless
    exists $self->column_info($col)->{_inflate_info};

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
    if (ref $attrs->{$key}
          && exists $class->column_info($key)->{_inflate_info}) {
      $attrs->{$key} = $class->_deflated_column($key, $attrs->{$key});
    }
  }
  return $class->next::method($attrs, @rest);
}

1;

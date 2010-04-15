package DBIx::Class::FilterColumn;

use strict;
use warnings;

use base qw/DBIx::Class::Row/;

sub filter_column {
  my ($self, $col, $attrs) = @_;

  $self->throw_exception("No such column $col to filter")
    unless $self->has_column($col);

  $self->throw_exception("filter_column needs attr hashref")
    unless ref $attrs eq 'HASH';

  $self->column_info($col)->{_filter_info} = $attrs;
  my $acc = $self->column_info($col)->{accessor};
  $self->mk_group_accessors('value' => [ (defined $acc ? $acc : $col), $col]);
  return 1;
}

sub _column_from_storage {
  my ($self, $col, $value) = @_;

  return $value unless defined $value;

  my $info = $self->column_info($col)
    or $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $filter = $info->{_filter_info}{from_storage};
  $self->throw_exception("No inflator for $col") unless defined $filter;

  return $self->$filter($value);
}

sub _column_to_storage {
  my ($self, $col, $value) = @_;

  my $info = $self->column_info($col) or
    $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $unfilter = $info->{_filter_info}{to_storage};
  $self->throw_exception("No unfilter for $col") unless defined $unfilter;
  return $self->$unfilter($value);
}

sub get_value {
  my ($self, $col) = @_;

  $self->throw_exception("$col is not a filtered column")
    unless exists $self->column_info($col)->{_filter_info};

  return $self->{_filtered_column}{$col}
    if exists $self->{_filtered_column}{$col};

  my $val = $self->get_column($col);

  return $self->{_filtered_column}{$col} = $self->_column_from_storage($col, $val);
}

sub set_value {
  my ($self, $col, $filtered) = @_;

  $self->set_column($col, $self->_column_to_storage($col, $filtered));

  delete $self->{_filtered_column}{$col};

  return $filtered;
}

sub update {
  my ($self, $attrs, @rest) = @_;
  foreach my $key (keys %{$attrs||{}}) {
    if ($self->has_column($key) &&
          exists $self->column_info($key)->{_filter_info}) {
      my $val = delete $attrs->{$key};
      $self->set_value($key, $val);
      $attrs->{$key} = $self->_column_to_storage($key, $val)
    }
  }
  return $self->next::method($attrs, @rest);
}


sub new {
  my ($class, $attrs, @rest) = @_;
  foreach my $key (keys %{$attrs||{}}) {
    if ($class->has_column($key) &&
          exists $class->column_info($key)->{_filter_info} ) {
      $attrs->{$key} = $class->_column_to_storage($key, delete $attrs->{$key})
    }
  }
  my $obj = $class->next::method($attrs, @rest);
  return $obj;
}


1;

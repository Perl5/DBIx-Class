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
  $self->mk_group_accessors('filtered_column' => [ (defined $acc ? $acc : $col), $col]);
  return 1;
}

sub _filtered_column {
  my ($self, $col, $value) = @_;

  return $value unless defined $value;

  my $info = $self->column_info($col)
    or $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $filter = $info->{_filter_info}{filter};
  $self->throw_exception("No inflator for $col") unless defined $filter;

  return $self->$filter($value);
}

sub _unfiltered_column {
  my ($self, $col, $value) = @_;

  my $info = $self->column_info($col) or
    $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $unfilter = $info->{_filter_info}{unfilter};
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

  return $self->{_filtered_column}{$col} = $self->_filtered_column($col, $val);
}

sub set_value {
  my ($self, $col, $filtered) = @_;

  $self->set_column($col, $self->_unfiltered_column($col, $filtered));

  delete $self->{_filtered_column}{$col};

  return $filtered;
}

sub register_column {
  my ($class, $col, $info) = @_;
  my $acc = $col;
  if (exists $info->{accessor}) {
    return unless defined $info->{accessor};
    $acc = [ $info->{accessor}, $col ];
  }
  if ( exists $self->column_info($col)->{_filter_info} ) {
     $class->mk_group_accessors(value => $acc);
  } else {
     $class->mk_group_accessors(column => $acc);
  }
}

1;

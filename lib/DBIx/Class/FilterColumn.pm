package DBIx::Class::FilterColumn;
use strict;
use warnings;

use base qw/DBIx::Class::Row/;

sub filter_column {
  my ($self, $col, $attrs) = @_;

  $self->throw_exception("FilterColumn does not work with InflateColumn")
    if $self->isa('DBIx::Class::InflateColumn') &&
      defined $self->column_info($col)->{_inflate_info};

  $self->throw_exception("No such column $col to filter")
    unless $self->has_column($col);

  $self->throw_exception("filter_column needs attr hashref")
    unless ref $attrs eq 'HASH';

  $self->column_info($col)->{_filter_info} = $attrs;
  my $acc = $self->column_info($col)->{accessor};
  $self->mk_group_accessors(filtered_column => [ (defined $acc ? $acc : $col), $col]);
  return 1;
}

sub _column_from_storage {
  my ($self, $col, $value) = @_;

  return $value unless defined $value;

  my $info = $self->column_info($col)
    or $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $filter = $info->{_filter_info}{filter_from_storage};
  $self->throw_exception("No filter for $col") unless defined $filter;

  return $self->$filter($value);
}

sub _column_to_storage {
  my ($self, $col, $value) = @_;

  my $info = $self->column_info($col) or
    $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $unfilter = $info->{_filter_info}{filter_to_storage};
  $self->throw_exception("No unfilter for $col") unless defined $unfilter;
  return $self->$unfilter($value);
}

sub get_filtered_column {
  my ($self, $col) = @_;

  $self->throw_exception("$col is not a filtered column")
    unless exists $self->column_info($col)->{_filter_info};

  return $self->{_filtered_column}{$col}
    if exists $self->{_filtered_column}{$col};

  my $val = $self->get_column($col);

  return $self->{_filtered_column}{$col} = $self->_column_from_storage($col, $val);
}

sub get_column {
  my ($self, $col) = @_;
  if (exists $self->{_filtered_column}{$col}) {
    return $self->{_column_data}{$col} ||= $self->_column_to_storage ($col, $self->{_filtered_column}{$col});
  }

  return $self->next::method ($col);
}

# sadly a separate codepath in Row.pm ( used by insert() )
sub get_columns {
  my $self = shift;

  foreach my $col (keys %{$self->{_filtered_column}||{}}) {
    $self->{_column_data}{$col} ||= $self->_column_to_storage ($col, $self->{_filtered_column}{$col})
      if exists $self->{_filtered_column}{$col};
  }

  $self->next::method (@_);
}

sub store_column {
  my ($self, $col) = (shift, @_);

  # blow cache
  delete $self->{_filtered_column}{$col};

  $self->next::method(@_);
}

sub set_filtered_column {
  my ($self, $col, $filtered) = @_;

  # do not blow up the cache via set_column unless necessary
  # (filtering may be expensive!)
  if (exists $self->{_filtered_column}{$col}) {
    return $filtered
      if ($self->_eq_column_values ($col, $filtered, $self->{_filtered_column}{$col} ) );

    $self->make_column_dirty ($col); # so the comparison won't run again
  }

  $self->set_column($col, $self->_column_to_storage($col, $filtered));

  return $self->{_filtered_column}{$col} = $filtered;
}

sub update {
  my ($self, $attrs, @rest) = @_;

  foreach my $key (keys %{$attrs||{}}) {
    if (
      $self->has_column($key)
        &&
      exists $self->column_info($key)->{_filter_info}
    ) {
      $self->set_filtered_column($key, delete $attrs->{$key});

      # FIXME update() reaches directly into the object-hash
      # and we may *not* have a filtered value there - thus
      # the void-ctx filter-trigger
      $self->get_column($key) unless exists $self->{_column_data}{$key};
    }
  }

  return $self->next::method($attrs, @rest);
}

sub new {
  my ($class, $attrs, @rest) = @_;
  my $source = $attrs->{-result_source}
    or $class->throw_exception('Sourceless rows are not supported with DBIx::Class::FilterColumn');

  my $obj = $class->next::method($attrs, @rest);
  foreach my $key (keys %{$attrs||{}}) {
    if ($obj->has_column($key) &&
          exists $obj->column_info($key)->{_filter_info} ) {
      $obj->set_filtered_column($key, $attrs->{$key});
    }
  }

  return $obj;
}

1;

=head1 NAME

DBIx::Class::FilterColumn - Automatically convert column data

=head1 SYNOPSIS

 # In your result classes
 __PACKAGE__->filter_column( money => {
     filter_to_storage => 'to_pennies',
     filter_from_storage => 'from_pennies',
 });

 sub to_pennies   { $_[1] * 100 }

 sub from_pennies { $_[1] / 100 }

 1;

=head1 DESCRIPTION

This component is meant to be a more powerful, but less DWIM-y,
L<DBIx::Class::InflateColumn>.  One of the major issues with said component is
that it B<only> works with references.  Generally speaking anything that can
be done with L<DBIx::Class::InflateColumn> can be done with this component.

=head1 METHODS

=head2 filter_column

 __PACKAGE__->filter_column( colname => {
     filter_from_storage => 'method',
     filter_to_storage   => 'method',
 })

This is the method that you need to call to set up a filtered column.  It takes
exactly two arguments; the first being the column name the second being a
C<HashRef> with C<filter_from_storage> and C<filter_to_storage> having
something that can be called as a method.  The method will be called with
the value of the column as the first non-C<$self> argument.

=head2 get_filtered_column

 $obj->get_filtered_column('colname')

Returns the filtered value of the column

=head2 set_filtered_column

 $obj->set_filtered_column(colname => 'new_value')

Sets the filtered value of the column

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
  $self->mk_group_accessors(filtered_column => [ (defined $acc ? $acc : $col), $col]);
  return 1;
}

sub _column_from_storage {
  my ($self, $source, $col, $value) = @_;

  return $value unless defined $value;

  my $info = $self->column_info($col)
    or $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $filter = $info->{_filter_info}{filter_from_storage};
  $self->throw_exception("No inflator for $col") unless defined $filter;

  return $source->$filter($value);
}

sub _column_to_storage {
  my ($self, $source, $col, $value) = @_;

  my $info = $self->column_info($col) or
    $self->throw_exception("No column info for $col");

  return $value unless exists $info->{_filter_info};

  my $unfilter = $info->{_filter_info}{filter_to_storage};
  $self->throw_exception("No unfilter for $col") unless defined $unfilter;
  return $source->$unfilter($value);
}

sub get_filtered_column {
  my ($self, $col) = @_;

  $self->throw_exception("$col is not a filtered column")
    unless exists $self->column_info($col)->{_filter_info};

  return $self->{_filtered_column}{$col}
    if exists $self->{_filtered_column}{$col};

  my $val = $self->get_column($col);

  return $self->{_filtered_column}{$col} = $self->_column_from_storage($self->result_source, $col, $val);
}

sub set_filtered_column {
  my ($self, $col, $filtered) = @_;

  $self->set_column($col, $self->_column_to_storage($self->result_source, $col, $filtered));

  delete $self->{_filtered_column}{$col};

  return $filtered;
}

sub update {
  my ($self, $attrs, @rest) = @_;
  foreach my $key (keys %{$attrs||{}}) {
    if ($self->has_column($key) &&
          exists $self->column_info($key)->{_filter_info}) {
      my $val = delete $attrs->{$key};
      $self->set_filtered_column($key, $val);
      $attrs->{$key} = $self->_column_to_storage($self->result_source, $key, $val)
    }
  }
  return $self->next::method($attrs, @rest);
}


sub new {
  my ($class, $attrs, @rest) = @_;
  my $source = delete $attrs->{-result_source}
    or $class->throw_exception('Sourceless rows are not supported with DBIx::Class::FilterColumn');

  foreach my $key (keys %{$attrs||{}}) {
    if ($class->has_column($key) &&
          exists $class->column_info($key)->{_filter_info} ) {
      $attrs->{$key} = $class->_column_to_storage($source, $key, delete $attrs->{$key})
    }
  }
  my $obj = $class->next::method($attrs, @rest);
  return $obj;
}

1;

=head1 THE ONE TRUE WAY

 package My::Reusable::Filter;

 sub to_pennies   { $_[1] * 100 }
 sub from_pennies { $_[1] / 100 }

 1;

 package My::Schema::Result::Account;

 use strict;
 use warnings;

 use base 'DBIx::Class::Core';

 __PACKAGE->load_components('FilterColumn');

 __PACKAGE__->add_columns(
   id => {
     data_type => 'int',
     is_auto_increment => 1,
   },
   total_money => {
     data_type => 'int',
   },
 );

 __PACKAGE__->set_primary_key('id');

 __PACKAGE__->filter_column(total_money => {
   filter_to_storage   => 'to_pennies',
   filter_from_storage => 'from_pennies',
 });

 1;


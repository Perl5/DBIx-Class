package # hide from PAUSE
    DBIx::Class::CDBICompat::Retrieve;

use strict;
use warnings FATAL => 'all';


sub retrieve {
  my $self = shift;
  die "No args to retrieve" unless @_ > 0;

  my @cols = $self->primary_columns;

  my $query;
  if (ref $_[0] eq 'HASH') {
    $query = { %{$_[0]} };
  }
  elsif (@_ == @cols) {
    $query = {};
    @{$query}{@cols} = @_;
  }
  else {
    $query = {@_};
  }

  $query = $self->_build_query($query);
  $self->find($query);
}

sub find_or_create {
  my $self = shift;
  my $query = ref $_[0] eq 'HASH' ? shift : {@_};

  $query = $self->_build_query($query);
  $self->next::method($query);
}

# _build_query
#
# Build a query hash. Defaults to a no-op; ColumnCase overrides.

sub _build_query {
  my ($self, $query) = @_;

  return $query;
}

sub retrieve_from_sql {
  my ($class, $cond, @rest) = @_;

  $cond =~ s/^\s*WHERE//i;

  if( $cond =~ s/\bLIMIT (\d+)\s*$//i ) {
      push @rest, { rows => $1 };
  }

  if ( $cond =~ s/\bORDER\s+BY\s+(.*)$//i ) {
    push @rest, { order_by => $1 };
  }

  return $class->search_literal($cond, @rest);
}

sub construct {
    my $class = shift;
    my $obj = $class->resultset_instance->new_result(@_);
    $obj->in_storage(1);
    
    return $obj;
}

sub retrieve_all      { shift->search              }
sub count_all         { shift->count               }

sub maximum_value_of  {
    my($class, $col) = @_;
    return $class->resultset_instance->get_column($col)->max;
}

sub minimum_value_of  {
    my($class, $col) = @_;
    return $class->resultset_instance->get_column($col)->min;
}

1;

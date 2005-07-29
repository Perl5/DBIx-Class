package DBIx::Class::PK;

use strict;
use warnings;

use base qw/Class::Data::Inheritable DBIx::Class::SQL/;

__PACKAGE__->mk_classdata('_primaries' => {});

sub _ident_cond {
  my ($class) = @_;
  return join(" AND ", map { "$_ = ?" } keys %{$class->_primaries});
}

sub _ident_values {
  my ($self) = @_;
  return (map { $self->{_column_data}{$_} } keys %{$self->_primaries});
}

sub set_primary_key {
  my ($class, @cols) = @_;
  my %pri;
  $pri{$_} = {} for @cols;
  $class->_primaries(\%pri);
}

sub retrieve {
  my ($class, @vals) = @_;
  my $attrs = (@vals > 1 && ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});
  my @pk = keys %{$class->_primaries};
  die "Can't retrieve unless primary columns are defined" unless @pk;
  my $query;
  if (ref $vals[0] eq 'HASH') {
    $query = $vals[0];
  } elsif (@pk == @vals) {
    my $ret = ($class->retrieve_from_sql($class->_ident_cond, @vals, $attrs))[0];
    #warn "$class: ".join(', ', %{$ret->{_column_data}});
    return $ret;
  } else {
    $query = {@vals};
  }
  die "Can't retrieve unless all primary keys are specified"
    unless (keys %$query >= @pk); # If we check 'em we run afoul of uc/lc
                                  # column names etc. Not sure what to do yet
  my $ret = ($class->search($query))[0];
  #warn "$class: ".join(', ', %{$ret->{_column_data}});
  return $ret;
}

sub discard_changes {
  my ($self) = @_;
  delete $self->{_dirty_columns};
  return unless $self->in_database; # Don't reload if we aren't real!
  my ($reload) = $self->retrieve($self->id);
  unless ($reload) { # If we got deleted in the mean-time
    $self->in_database(0);
    return $self;
  }
  $self->store_column($_ => $reload->get_column($_))
    foreach keys %{$self->_columns};
  return $self;
}

sub id {
  my ($self) = @_;
  die "Can't call id() as a class method" unless ref $self;
  my @pk = $self->_ident_values;
  return (wantarray ? @pk : $pk[0]);
}

1;

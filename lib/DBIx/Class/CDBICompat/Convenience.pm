package DBIx::Class::CDBICompat::Convenience;

use strict;
use warnings;

sub find_or_create {
  my $class    = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my ($exists) = $class->search($hash);
  return defined($exists) ? $exists : $class->create($hash);
}

sub id {
  my ($self) = @_;
  die "Can't call id() as a class method" unless ref $self;
  my @pk = $self->_ident_value;
  return (wantarray ? @pk : $pk[0]);
}

#sub insert {
#  my $self = shift;
#  $self->NEXT::insert(@_);
#  my @pk = keys %{ $self->_primaries };
#  if ((@pk == 1) && (!$self->{_column_data}{$pk[0]})) {
#    $self->{_column_data}{$pk[0]} = $self->_get_dbh->last_insert_id;
#  }
#  return $self;
#}

sub retrieve_all {
  my ($class) = @_;
  return $class->search( { 1 => 1 } );
}

1;

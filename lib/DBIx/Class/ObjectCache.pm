package DBIx::Class::ObjectCache;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('cache');

sub insert {
  my $self = shift;
  $self->NEXT::ACTUAL::insert(@_);
  $self->_insert_into_cache if $self->cache;  
  return $self;
}

sub find {
  my ($self,@vals) = @_;
  return $self->NEXT::ACTUAL::find(@vals) unless $self->cache;
  
  # this is a terrible hack here. I know it can be improved.
  # but, it's a start anyway. probably find in PK.pm needs to
  # call a hook, or some such thing. -Dave/ningu
  my ($object,$key);
  my @pk = keys %{$self->_primaries};
  if (ref $vals[0] eq 'HASH') {
    my $cond = $vals[0]->{'-and'};
    $key = $self->_create_ID(%{$cond->[0]}) if ref $cond eq 'ARRAY';
  } elsif (@pk == @vals) {
    my %data;
    @data{@pk} = @vals;
    $key = $self->_create_ID(%data);
  } else {
    $key = $self->_create_ID(@vals);
  }
  if ($key and $object = $self->cache->get($key)) {
    return $object;
  }
  
  $object = $self->NEXT::ACTUAL::find(@vals);
  $object->_insert_into_cache if $object;
  return $object;
}

sub update {
  my $self = shift;
  $self->cache->remove($self->ID) if $self->cache;
  return $self->NEXT::ACTUAL::update(@_);
}

sub delete {
  my $self = shift;
  $self->cache->remove($self->ID) if $self->cache;
  return $self->NEXT::ACTUAL::delete(@_);
}

sub _insert_into_cache {
  my ($self) = @_;
  if (my $key = $self->ID) {
    if (my $object = $self->new( $self->{_column_data} )) {
      $self->cache->set($key,$object);
    }
  }
}

1;

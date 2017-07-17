package # hide from PAUSE
    DBIx::Class::CDBICompat::AttributeAPI;

use strict;
use warnings;

use base 'DBIx::Class';

sub _attrs {
  my ($self, @atts) = @_;
  return @{$self->{_column_data}}{@atts};
}

sub _attr { shift->_attrs(@_) }

sub _attribute_store {
  my $self   = shift;
  my $vals   = @_ == 1 ? shift: {@_};
  $self->store_column($_, $vals->{$_}) for keys %{$vals};
}

sub _attribute_set {
  my $self   = shift;
  my $vals   = @_ == 1 ? shift: {@_};
  $self->set_column($_, $vals->{$_}) for keys %{$vals};
}

sub _attribute_delete {
  my ($self, $attr) = @_;
  delete $self->{_column_data}{$attr};
}

sub _attribute_exists {
  my ($self, $attr) = @_;
  $self->has_column_loaded($attr);
}

1;

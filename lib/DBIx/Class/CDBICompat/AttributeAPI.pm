package DBIx::Class::CDBICompat::AttributeAPI;

sub _attrs {
  my ($self, @atts) = @_;
  return @{$self->{_column_data}}{@atts};
}

*_attr = \&_attrs;

sub _attribute_store {
  my $self   = shift;
  my $vals   = @_ == 1 ? shift: {@_};
  my (@cols) = keys %$vals;
  @{$self->{_column_data}}{@cols} = @{$vals}{@cols};
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
  exists $self->{_column_data}{$attr};
}

1;

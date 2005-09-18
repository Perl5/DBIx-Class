package DBIx::Class::Relationship::CascadeActions;

sub delete {
  my ($self, @rest) = @_;
  return $self->NEXT::ACTUAL::delete(@rest) unless ref $self;
    # I'm just ignoring this for class deletes because hell, the db should
    # be handling this anyway. Assuming we have joins we probably actually
    # *could* do them, but I'd rather not.

  my $ret = $self->NEXT::ACTUAL::delete(@rest);

  my %rels = %{ $self->_relationships };
  my @cascade = grep { $rels{$_}{attrs}{cascade_delete} } keys %rels;
  foreach my $rel (@cascade) {
    $self->search_related($rel)->delete;
  }
  return $ret;
}

sub update {
  my ($self, @rest) = @_;
  return $self->NEXT::ACTUAL::update(@rest) unless ref $self;
    # Because update cascades on a class *really* don't make sense!

  my $ret = $self->NEXT::ACTUAL::update(@rest);

  my %rels = %{ $self->_relationships };
  my @cascade = grep { $rels{$_}{attrs}{cascade_update} } keys %rels;
  foreach my $rel (@cascade) {
    $_->update for $self->$rel;
  }
  return $ret;
}

1;

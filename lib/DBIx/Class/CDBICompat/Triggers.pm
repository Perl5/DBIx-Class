package DBIx::Class::CDBICompat::Triggers;

use Class::Trigger;

sub insert {
  my $self = shift;
  $self->call_trigger('before_create');
  $self->NEXT::insert(@_);
  $self->call_trigger('after_create');
  return $self;
}

sub update {
  my $self = shift;
  $self->call_trigger('before_update');
  my @to_update = keys %{$self->{_dirty_columns} || {}};
  return -1 unless @to_update;
  $self->NEXT::update(@_);
  $self->call_trigger('after_update');
  return $self;
}

sub delete {
  my $self = shift;
  $self->call_trigger('before_delete') if ref $self;
  $self->NEXT::delete(@_);
  $self->call_trigger('after_delete') if ref $self;
  return $self;
}

1;

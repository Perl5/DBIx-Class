package DBIx::Class::PK::Auto;

use strict;
use warnings;

sub insert {
  my ($self, @rest) = @_;
  my $ret = $self->NEXT::ACTUAL::insert(@rest);
  my ($pri, $too_many) =
    (grep { $self->_primaries->{$_}{'auto_increment'} }
       keys %{ $self->_primaries })
    || (keys %{ $self->_primaries });
  die "More than one possible key found for auto-inc on ".ref $self
    if $too_many;
  unless (defined $self->get_column($pri)) {
    die "Can't auto-inc for $pri on ".ref $self.": no _last_insert_id method"
      unless $self->can('_last_insert_id');
    my $id = $self->_last_insert_id;
    die "Can't get last insert id" unless $id;
    $self->store_column($pri => $id);
  }
  return $ret;
}

1;

package DBIx::Class::CDBICompat::LiveObjectIndex;

use strict;
use warnings;

use Scalar::Util qw/weaken/;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('purge_object_index_every' => 1000);
__PACKAGE__->mk_classdata('live_object_index' => { });
__PACKAGE__->mk_classdata('live_object_init_count' => { });

# Ripped from Class::DBI 0.999, all credit due to Tony Bowden for this code,
# all blame due to me for whatever bugs I introduced porting it.

sub _live_object_key {
  my ($me) = @_;
  my $class   = ref($me) || $me;
  my @primary = keys %{$class->_primaries};

  # no key unless all PK columns are defined
  return "" unless @primary == grep defined $me->get_column($_), @primary;

  # create single unique key for this object
  return join "\030", $class, map { $_ . "\032" . $me->get_column($_) }
                                sort @primary;
}

sub purge_dead_from_object_index {
  my $live = $_[0]->live_object_index;
  delete @$live{ grep !defined $live->{$_}, keys %$live };
}

sub remove_from_object_index {
  my $self    = shift;
  my $obj_key = $self->_live_object_key;
  delete $self->live_object_index->{$obj_key};
}

sub clear_object_index {
  my $live = $_[0]->live_object_index;
  delete @$live{ keys %$live };
}

# And now the fragments to tie it in to DBIx::Class::Table

sub insert {
  my ($self, @rest) = @_;
  $self->NEXT::ACTUAL::insert(@rest);
    # Because the insert will die() if it can't insert into the db (or should)
    # we can be sure the object *was* inserted if we got this far. In which
    # case, given primary keys are unique and _live_object_key only returns a
    # value if the object has all its primary keys, we can be sure there
    # isn't a real one in the object index already because such a record
    # cannot have existed without the insert failing.
  if (my $key = $self->_live_object_key) {
    my $live = $self->live_object_index;
    weaken($live->{$key} = $self);
    $self->purge_dead_from_object_index
      if ++$self->live_object_init_count->{count}
              % $self->purge_object_index_every == 0;
  }
  #use Data::Dumper; warn Dumper($self);
  return $self;
}

sub _row_to_object {
  my ($class, @rest) = @_;
  my $new = $class->NEXT::ACTUAL::_row_to_object(@rest);
  if (my $key = $new->_live_object_key) {
    #warn "Key $key";
    my $live = $class->live_object_index;
    return $live->{$key} if $live->{$key};
    weaken($live->{$key} = $new);
    $class->purge_dead_from_object_index
      if ++$class->live_object_init_count->{count}
              % $class->purge_object_index_every == 0;
  }
  return $new;
}

sub discard_changes {
  my ($self) = @_;
  if (my $key = $self->_live_object_key) {
    $self->remove_from_object_index;
    my $ret = $self->NEXT::ACTUAL::discard_changes;
    $self->live_object_index->{$key} = $self if $self->in_database;
    return $ret;
  } else {
    return $self->NEXT::ACTUAL::discard_changes;
  }
}

1;

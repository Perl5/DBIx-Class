package # Hide from PAUSE
  DBIx::Class::SQLAHacks::SQLite;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

#
# SQLite does not understand SELECT ... FOR UPDATE
# Adjust SQL here instead
#
sub select {
  my $self = shift;
  local $self->{_dbic_rs_attrs}{for} = undef;
  return $self->SUPER::select (@_);
}

1;

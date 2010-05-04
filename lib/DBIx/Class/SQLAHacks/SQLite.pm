package # Hide from PAUSE
  DBIx::Class::SQLAHacks::SQLite;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

#
# SQLite does not understand SELECT ... FOR UPDATE
# Disable it here
#
sub _parse_rs_attrs {
  my ($self, $attrs) = @_;

  return $self->SUPER::_parse_rs_attrs ($attrs)
    if ref $attrs ne 'HASH';

  local $attrs->{for};
  return $self->SUPER::_parse_rs_attrs ($attrs);
}

1;

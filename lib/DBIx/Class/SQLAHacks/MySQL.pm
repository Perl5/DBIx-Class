package # Hide from PAUSE
  DBIx::Class::SQLAHacks::MySQL;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

#
# MySQL does not understand the standard INSERT INTO $table DEFAULT VALUES
# Adjust SQL here instead
#
sub insert {
  my $self = shift;

  my $table = $_[0];
  $table = $self->_quote($table);

  if (! $_[1] or (ref $_[1] eq 'HASH' and !keys %{$_[1]} ) ) {
    return "INSERT INTO ${table} () VALUES ()"
  }

  return $self->SUPER::insert (@_);
}

# Allow STRAIGHT_JOIN's
sub _generate_join_clause {
    my ($self, $join_type) = @_;

    if( $join_type && $join_type =~ /^STRAIGHT\z/i ) {
        return ' STRAIGHT_JOIN '
    }

    return $self->SUPER::_generate_join_clause( $join_type );
}
1;

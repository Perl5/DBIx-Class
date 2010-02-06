package # Hide from PAUSE
  DBIx::Class::SQLAHacks::ODBC::Firebird;

use strict;
use warnings;
use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

sub insert {
  my $self = shift;
  my ($table, $vals, $opts) = @_;

# Quoting RETURNING values breaks the Firebird ODBC driver, so we convert to
# scalarref with unquoted values.
  my $returning = $opts->{returning};

  if ($returning && ref $returning eq 'ARRAY') {
    $opts->{returning} = \join ', ' => @$returning;
  }

  return $self->next::method(@_);
}

1;

package DBIx::Class::Storage::DBI::InterBase;

# mostly stolen from DBIx::Class::Storage::DBI::MSSQL

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::AmbiguousGlob DBIx::Class::Storage::DBI/;
use mro 'c3';

use List::Util();

__PACKAGE__->mk_group_accessors(simple => qw/
  _identity
/);

sub insert_bulk {
  my $self = shift;
  my ($source, $cols, $data) = @_;

  my $is_identity_insert = (List::Util::first
      { $source->column_info ($_)->{is_auto_increment} }
      (@{$cols})
  )
     ? 1
     : 0;

  $self->next::method(@_);
}


sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  my ($sql, $bind) = $self->next::method (@_);

  if ($op eq 'insert') {
    $sql .= 'RETURNING "Id"';

  }

  return ($sql, $bind);
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);

  if ($op eq 'insert') {

    # this should bring back the result of SELECT SCOPE_IDENTITY() we tacked
    # on in _prep_for_execute above
    local $@;
    my ($identity) = eval { $sth->fetchrow_array };

    $self->_identity($identity);
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id { shift->_identity }

1;


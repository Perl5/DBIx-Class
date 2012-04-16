package DBIx::Class::Storage::DBI::ODBC;
use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

sub _rebless {
  my ($self) = @_;

  if (my $dbtype = $self->_dbh_get_info('SQL_DBMS_NAME')) {
    # Translate the backend name into a perl identifier
    $dbtype =~ s/\W/_/gi;
    my $subclass = "DBIx::Class::Storage::DBI::ODBC::${dbtype}";

    return if $self->isa($subclass);

    if ($self->load_optional_class($subclass)) {
      bless $self, $subclass;
      $self->_rebless;
    }
    else {
      warn "Expected driver '$subclass' not found, using generic support. " .
           "Please file an RT.\n";
    }
  }
  else {
    warn "Could not determine your database type, using generic support.\n";
  }
}

# Whether or not we are connecting via the freetds ODBC driver.
sub _using_freetds {
  my $self = shift;

  my $dsn = $self->_dbi_connect_info->[0];

  return 1 if (
    ( (! ref $dsn) and $dsn =~ /driver=FreeTDS/i)
      or
    ( ($self->_dbh_get_info('SQL_DRIVER_NAME')||'') =~ /tdsodbc/i )
  );

  return 0;
}

# Either returns the FreeTDS version via which we are connecting, 0 if can't
# be determined, or undef otherwise
sub _using_freetds_version {
  my $self = shift;
  return undef unless $self->_using_freetds;
  return $self->_dbh_get_info('SQL_DRIVER_VER') || 0;
}

sub _disable_odbc_array_ops {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  if (eval { DBD::ODBC->VERSION('1.35_01') }) {
    $dbh->{odbc_array_operations} = 0;
  }
  elsif (eval { DBD::ODBC->VERSION('1.33_01') }) {
    $dbh->{odbc_disable_array_operations} = 1;
  }
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC - Base class for ODBC drivers

=head1 DESCRIPTION

This class simply provides a mechanism for discovering and loading a sub-class
for a specific ODBC backend.  It should be transparent to the user.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

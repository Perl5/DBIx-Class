package DBIx::Class::Storage::DBI::ODBC;
use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

sub _rebless {
  my ($self) = @_;

  if (my $dbtype = $self->_dbh_get_info(17)) {
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

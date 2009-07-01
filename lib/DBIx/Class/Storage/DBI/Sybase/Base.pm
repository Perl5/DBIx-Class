package DBIx::Class::Storage::DBI::Sybase::Base;

use strict;
use warnings;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::Base - Common functionality for drivers using
L<DBD::Sybase>

=head1 METHODS

=head2 connected

Returns true if we have an open (and working) database connection, false if it
is not (yet) open (or does not work). (Executes a simple SELECT to make sure it
works.)

The reason this is needed is that L<DBD::Sybase>'s ping() does not work with an
active statement handle, leading to masked database errors.

=cut

sub connected {
  my $self = shift;

  my $dbh = $self->_dbh;
  local $dbh->{RaiseError} = 1;
  eval {
    $dbh->do('select 1');
  };

  return $@ ? 0 : 1;
}

1;

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

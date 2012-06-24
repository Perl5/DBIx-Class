package DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server::Cursor;

use strict;
use warnings;
use base 'DBIx::Class::Storage::DBI::Cursor';
use mro 'c3';
use DBIx::Class::Storage::DBI::ADO::CursorUtils qw/_normalize_guids _strip_trailing_binary_nulls/;
use namespace::clean;

=head1 NAME

DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server::Cursor - Remove trailing
NULLs in binary data and normalize GUIDs for MSSQL over ADO

=head1 DESCRIPTION

This class is for removing trailing C<NULL>s from binary data and removing braces
from GUIDs retrieved from Microsoft SQL Server over ADO.

You probably don't want to be here, see
L<DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server> for information on the
Microsoft SQL Server driver for ADO and L<DBIx::Class::Storage::DBI::MSSQL> for
the Microsoft SQL Server driver base class.

Unfortunately when using L<DBD::ADO>, binary data comes back padded with
trailing C<NULL>s and GUIDs come back wrapped in braces, the purpose of this
class is to remove the C<NULL>s and braces.
L<DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server> sets
L<cursor_class|DBIx::Class::Storage::DBI/cursor_class> to this class by
default. It is overridable via your
L<connect_info|DBIx::Class::Storage::DBI/connect_info>.

You can use L<DBIx::Class::Cursor::Cached> safely with this class and not lose
the binary data normalizing functionality,
L<::Cursor::Cached|DBIx::Class::Cursor::Cached> uses the underlying class data
for the inner cursor class.

=cut

sub _dbh_next {
  my ($storage, $dbh, $self) = @_;

  my $next = $self->next::can;

  my @row = $next->(@_);

  my $col_infos = $storage->_resolve_column_info($self->args->[0]);

  my $select = $self->args->[1];

  _normalize_guids($select, $col_infos, \@row, $storage);
  _strip_trailing_binary_nulls($select, $col_infos, \@row, $storage);

  return @row;
}

sub _dbh_all {
  my ($storage, $dbh, $self) = @_;

  my $next = $self->next::can;

  my @rows = $next->(@_);

  my $col_infos = $storage->_resolve_column_info($self->args->[0]);

  my $select = $self->args->[1];

  for (@rows) {
    _normalize_guids($select, $col_infos, $_, $storage);
    _strip_trailing_binary_nulls($select, $col_infos, $_, $storage);
  }

  return @rows;
}

1;

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

# vim:sts=2 sw=2:

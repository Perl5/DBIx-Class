package DBIx::Class::Storage::DBI::SQLAnywhere::Cursor;

use strict;
use warnings;
use base 'DBIx::Class::Storage::DBI::Cursor';
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::SQLAnywhere::Cursor - GUID Support for SQL Anywhere
over L<DBD::SQLAnywhere>

=head1 DESCRIPTION

This class is for normalizing GUIDs retrieved from SQL Anywhere via
L<DBD::SQLAnywhere>.

You probably don't want to be here, see
L<DBIx::Class::Storage::DBI::SQLAnywhere> for information on the SQL Anywhere
driver.

Unfortunately when using L<DBD::SQLAnywhere>, GUIDs come back in binary, the
purpose of this class is to transform them to text.
L<DBIx::Class::Storage::DBI::SQLAnywhere> sets
L<cursor_class|DBIx::Class::Storage::DBI/cursor_class> to this class by default.
It is overridable via your
L<connect_info|DBIx::Class::Storage::DBI/connect_info>.

You can use L<DBIx::Class::Cursor::Cached> safely with this class and not lose
the GUID normalizing functionality,
L<::Cursor::Cached|DBIx::Class::Cursor::Cached> uses the underlying class data
for the inner cursor class.

=cut

sub _dbh_next {
  my ($storage, $dbh, $self) = @_;

  my $next = $self->next::can;

  my @row = $next->(@_);

  my $col_info = $storage->_resolve_column_info($self->args->[0]);

  my $select = $self->args->[1];

  for my $select_idx (0..$#$select) {
    my $selected = $select->[$select_idx];

    next if ref $selected;

    my $data_type = $col_info->{$selected}{data_type};

    if ($storage->_is_guid_type($data_type)) {
      my $returned = $row[$select_idx];

      if (length $returned == 16) {
        $row[$select_idx] = $storage->_uuid_to_str($returned);
      }
    }
  }

  return @row;
}

sub _dbh_all {
  my ($storage, $dbh, $self) = @_;

  my $next = $self->next::can;

  my @rows = $next->(@_);

  my $col_info = $storage->_resolve_column_info($self->args->[0]);

  my $select = $self->args->[1];

  for my $row (@rows) {
    for my $select_idx (0..$#$select) {
      my $selected = $select->[$select_idx];

      next if ref $selected;

      my $data_type = $col_info->{$selected}{data_type};

      if ($storage->_is_guid_type($data_type)) {
        my $returned = $row->[$select_idx];

        if (length $returned == 16) {
          $row->[$select_idx] = $storage->_uuid_to_str($returned);
        }
      }
    }
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

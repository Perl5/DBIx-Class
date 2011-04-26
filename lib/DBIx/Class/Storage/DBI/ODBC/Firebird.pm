package DBIx::Class::Storage::DBI::ODBC::Firebird;

use strict;
use warnings;
use base 'DBIx::Class::Storage::DBI::Firebird::Common';
use mro 'c3';
use Try::Tiny;
use namespace::clean;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Firebird - Driver for using the Firebird RDBMS
through ODBC

=head1 DESCRIPTION

Most functionality is provided by
L<DBIx::Class::Storage::DBI::Firebird::Common>, see that driver for details.

To build the ODBC driver for Firebird on Linux for unixODBC, see:

L<http://www.firebirdnews.org/?p=1324>

This driver does not suffer from the nested statement handles across commits
issue that the L<DBD::InterBase|DBIx::Class::Storage::DBI::InterBase> or the
L<DBD::Firebird|DBIx::Class::Storage::DBI::Firebird> based driver does. This
makes it more suitable for long running processes such as under L<Catalyst>.

=cut

__PACKAGE__->datetime_parser_type ('DBIx::Class::Storage::DBI::ODBC::Firebird::DateTime::Format');

# releasing savepoints doesn't work for some reason, but that shouldn't matter
sub _exec_svp_release { 1 }

sub _exec_svp_rollback {
  my ($self, $name) = @_;

  try {
    $self->_dbh->do("ROLLBACK TO SAVEPOINT $name")
  }
  catch {
    # Firebird ODBC driver bug, ignore
    if (not /Unable to fetch information about the error/) {
      $self->throw_exception($_);
    }
  };
}

package # hide from PAUSE
  DBIx::Class::Storage::DBI::ODBC::Firebird::DateTime::Format;

# inherit parse/format date
our @ISA = 'DBIx::Class::Storage::DBI::InterBase::DateTime::Format';

my $timestamp_format = '%Y-%m-%d %H:%M:%S.%4N'; # %F %T
my $timestamp_parser;

sub parse_datetime {
  shift;
  require DateTime::Format::Strptime;
  $timestamp_parser ||= DateTime::Format::Strptime->new(
    pattern  => $timestamp_format,
    on_error => 'croak',
  );
  return $timestamp_parser->parse_datetime(shift);
}

sub format_datetime {
  shift;
  require DateTime::Format::Strptime;
  $timestamp_parser ||= DateTime::Format::Strptime->new(
    pattern  => $timestamp_format,
    on_error => 'croak',
  );
  return $timestamp_parser->format_datetime(shift);
}

1;

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

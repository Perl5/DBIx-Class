package DBIx::Class::Storage::DBI::ODBC::Firebird;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI::InterBase/;
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Firebird - Driver for using the Firebird RDBMS
through ODBC

=head1 DESCRIPTION

Most functionality is provided by L<DBIx::Class::Storage::DBI::Interbase>, see
that module for details.

To build the ODBC driver for Firebird on Linux for unixODBC, see:

L<http://www.firebirdnews.org/?p=1324>

This driver does not suffer from the nested statement handles across commits
issue that the L<DBD::InterBase|DBIx::Class::Storage::DBI::InterBase> based
driver does. This makes it more suitable for long running processes such as
under L<Catalyst>.

=cut

# XXX seemingly no equivalent to ib_time_all from DBD::InterBase via ODBC
sub connect_call_datetime_setup { 1 }

# we don't need DBD::InterBase-specific initialization
sub _init { 1 }

# ODBC uses dialect 3 by default, good
sub _set_sql_dialect { 1 }

# releasing savepoints doesn't work, but that shouldn't matter
sub _svp_release { 1 }

sub datetime_parser_type {
  'DBIx::Class::Storage::DBI::ODBC::Firebird::DateTime::Format'
}

package # hide from PAUSE
  DBIx::Class::Storage::DBI::ODBC::Firebird::DateTime::Format;

# inherit parse/format date
our @ISA = 'DBIx::Class::Storage::DBI::InterBase::DateTime::Format';

my $timestamp_format = '%Y-%m-%d %H:%M:%S'; # %F %T, no fractional part
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

=head1 CAVEATS

=over 4

=item *

This driver (unlike L<DBD::InterBase>) does not currently support reading or
writing C<TIMESTAMP> values with sub-second precision.

=back

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

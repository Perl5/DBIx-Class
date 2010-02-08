package DBIx::Class::Storage::DBI::ODBC::Firebird;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI::InterBase/;
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Firebird - Driver for using the Firebird RDBMS
through ODBC

=head1 SYNOPSIS

Most functionality is provided by L<DBIx::Class::Storage::DBI::Interbase>, see
that module for details.

To build the ODBC driver for Firebird on Linux for unixODBC, see:

L<http://www.firebirdnews.org/?p=1324>

=cut

# XXX seemingly no equivalent to ib_time_all in DBD::InterBase via ODBC
sub connect_call_datetime_setup { 1 }

# from MSSQL

sub build_datetime_parser {
  my $self = shift;
  my $type = "DateTime::Format::Strptime";
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type->new(
    pattern => '%Y-%m-%d %H:%M:%S', # %F %T
    on_error => 'croak',
  );
}

1;

=head1 CAVEATS

This driver (unlike L<DBD::InterBase>) does not currently support reading or
writing C<TIMESTAMP> values with sub-second precision.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

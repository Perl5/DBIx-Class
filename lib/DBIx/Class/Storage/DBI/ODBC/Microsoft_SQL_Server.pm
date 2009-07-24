package DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MSSQL/;
use mro 'c3';

1;

__END__

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server - Support specific
to Microsoft SQL Server over ODBC

=head1 DESCRIPTION

This class implements support specific to Microsoft SQL Server over ODBC.  It is
loaded automatically by by DBIx::Class::Storage::DBI::ODBC when it detects a
MSSQL back-end.

Most of the functionality is provided from the superclass
L<DBIx::Class::Storage::DBI::MSSQL>.

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim: sw=2 sts=2

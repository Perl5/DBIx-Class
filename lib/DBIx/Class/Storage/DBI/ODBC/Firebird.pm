package DBIx::Class::Storage::DBI::ODBC::Firebird;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI::InterBase/;
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Firebird - Driver for using the Firebird RDBMS
through ODBC

=head1 SYNOPSIS

All functionality is provided by L<DBIx::Class::Storage::DBI::Interbase>, see
that module for details.

=cut

# RETURNING ("foo") is broken in ODBC, but RETURNING (foo) works
sub _quote_column_for_returning {
  return $_[1];
}

1;

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

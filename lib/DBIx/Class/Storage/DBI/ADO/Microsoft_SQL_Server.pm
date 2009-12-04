package DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server;

use strict;
use warnings;

use base qw/
  DBIx::Class::Storage::DBI::ADO
  DBIx::Class::Storage::DBI::MSSQL
/;
use mro 'c3';

sub _rebless {
  my $self = shift;
  $self->_identity_method('@@identity');
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server - Support for Microsoft
SQL Server via DBD::ADO

=head1 SYNOPSIS

This subclass supports MSSQL server connections via L<DBD::ADO>.

=head1 DESCRIPTION

The MSSQL specific functionality is provided by
L<DBIx::Class::Storage::DBI::MSSQL>.

C<_identity_method> is set to C<@@identity>, as C<SCOPE_IDENTITY()> doesn't work
with L<DBD::ADO>. See L<DBIx::Class::Storage::DBI::MSSQL/IMPLEMENTATION NOTES>
for caveats regarding this.

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

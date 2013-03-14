package DBIx::Class::Storage::DBI::CSV;

use base 'DBIx::Class::Storage::DBI::SQL::Statement';
use mro 'c3';
use namespace::clean;

1;

=head1 NAME

DBIx::Class::Storage::DBI::SNMP - Support for CSV files via DBD::CSV

=head1 SYNOPSIS

This subclass supports CSV files via L<DBD::CSV>.

=head1 DESCRIPTION

This subclass is essentially just a stub that uses the super class
L<DBIx::Class::Storage::DBI::SQL::Statement>.  Patches welcome if
anything specific to this driver is required.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
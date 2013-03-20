package DBIx::Class::Storage::DBI::TreeData;

use base 'DBIx::Class::Storage::DBI::DBDFile';
use mro 'c3';
use namespace::clean;

1;

=head1 NAME

DBIx::Class::Storage::DBI::TreeData - Support for JSON-like tree data via DBD::TreeData

=head1 SYNOPSIS

This subclass supports JSON-like tree tables via L<DBD::TreeData>.

=head1 DESCRIPTION

This subclass is essentially just a stub that uses the super class
L<DBIx::Class::Storage::DBI::DBDFile>.  Patches welcome if
anything specific to this driver is required.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
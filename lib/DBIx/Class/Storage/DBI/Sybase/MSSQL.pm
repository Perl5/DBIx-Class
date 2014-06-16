package DBIx::Class::Storage::DBI::Sybase::MSSQL;

use strict;
use warnings;

use DBIx::Class::Carp;
use namespace::clean;

carp 'Setting of storage_type is redundant as connections through DBD::Sybase'
    .' are now properly recognized and reblessed into the appropriate subclass'
    .' (DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server in the'
    .' case of MSSQL). Please remove the explicit call to'
    .q/ $schema->storage_type('::DBI::Sybase::MSSQL')/
    .', as this storage class has been deprecated in favor of the autodetected'
    .' ::DBI::Sybase::Microsoft_SQL_Server';


use base qw/DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server/;
use mro 'c3';

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::MSSQL - (DEPRECATED) Legacy storage class for MSSQL via DBD::Sybase

=head1 NOTE

Connections through DBD::Sybase are now correctly recognized and reblessed
into the appropriate subclass (L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>
in the case of MSSQL). Please remove the explicit storage_type setting from your
schema.

=head1 SYNOPSIS

This subclass supports MSSQL connected via L<DBD::Sybase>.

  $schema->storage_type('::DBI::Sybase::MSSQL');
  $schema->connect_info('dbi:Sybase:....', ...);

=head1 AUTHOR AND CONTRIBUTORS

See L<AUTHOR|DBIx::Class/AUTHOR> and L<CONTRIBUTORS|DBIx::Class/CONTRIBUTORS> in DBIx::Class

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

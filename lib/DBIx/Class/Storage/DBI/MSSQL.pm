package DBIx::Class::Storage::DBI::MSSQL;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::Sybase/;

sub last_insert_id {
  my( $id ) = $_[0]->_dbh->selectrow_array('SELECT @@IDENTITY' );
  return $id;
}

sub build_datetime_parser {
  my $self = shift;
  my $type = "DateTime::Format::Strptime";
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type->new( pattern => '%m/%d/%Y %H:%M:%S' );
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::MSSQL - Storage::DBI subclass for MSSQL

=head1 SYNOPSIS

This subclass supports MSSQL.  As MSSQL is usually used via a
differently-named DBD such as L<DBD::Sybase>, it does not get
autodetected by DBD-type like the other drivers, and you will need to
specify this storage driver manually, as in:

  $schema->storage_type('::DBI::MSSQL');
  $schema->connect_info('dbi:Sybase:....', ...);

=head1 AUTHORS

Brian Cassidy <bricas@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

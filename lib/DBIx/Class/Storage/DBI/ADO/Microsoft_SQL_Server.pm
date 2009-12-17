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

sub source_bind_attributes {
  my ($self, $source) = @_;

  my $bind_attributes;
  foreach my $column ($source->columns) {

    my $data_type = $source->column_info($column)->{data_type} || '';
    $bind_attributes->{$column} = $self->bind_attribute_by_data_type($data_type)
      if $data_type;
    $bind_attributes->{$column}{ado_size} ||= 8000; # max VARCHAR
  }

  return $bind_attributes;
}

sub bind_attribute_by_data_type {
  my ($self, $data_type) = @_;

  my $max_size =
    $self->_mssql_max_data_type_representation_size_in_bytes->{$data_type};

  my $res = {};
  $res->{ado_size} = $max_size if $max_size;

  return $res;
}

# approximate
# XXX needs to support varchar(max) and varbinary(max)
sub _mssql_max_data_type_representation_size_in_bytes {
  my $self = shift;

  my $blob_max = $self->_get_dbh->{LongReadLen} || 32768;

  return +{
    char => 8000,
    varchar => 8000,
    binary => 8000,
    varbinary => 8000,
    nchar => 8000,
    nvarchar => 8000,
    numeric => 100,
    smallint => 100,
    tinyint => 100,
    smallmoney => 100,
    bigint => 100,
    bit => 100,
    decimal => 100,
    int => 100,
    money => 100,
    float => 100,
    real => 100,
    uniqueidentifier => 100,
    ntext => $blob_max,
    text => $blob_max,
    image => $blob_max,
    date => 100,
    datetime => 100,
    datetime2 => 100,
    datetimeoffset => 100,
    smalldatetime => 100,
    time => 100,
    timestamp => 100,
  }
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

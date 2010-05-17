package DBIx::Class::Storage::DBI::UniqueIdentifier;

use strict;
use warnings;
use base 'DBIx::Class::Storage::DBI';
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::UniqueIdentifier - Storage component for RDBMSes
supporting the 'uniqueidentifier' type

=head1 DESCRIPTION

This is a storage component for databases that support the C<uniqueidentifier>
type and the C<NEWID()> function for generating UUIDs.

UUIDs are generated automatically for PK columns with the C<uniqueidentifier>
L<data_type|DBIx::Class::ResultSource/data_type>, as well as non-PK with this
L<data_type|DBIx::Class::ResultSource/data_type> and
L<auto_nextval|DBIx::Class::ResultSource/auto_nextval>.

Currently used by L<DBIx::Class::Storage::DBI::MSSQL> and
L<DBIx::Class::Storage::DBI::SQLAnywhere>.

The composing class can define a C<_new_uuid> method to override the function
used to generate a new UUID.

=cut

sub _new_uuid { 'NEWID()' }

sub insert {
  my $self = shift;
  my ($source, $to_insert) = @_;

  my $supplied_col_info = $self->_resolve_column_info($source, [keys %$to_insert] );

  my %guid_cols;
  my @pk_cols = $source->primary_columns;
  my %pk_cols;
  @pk_cols{@pk_cols} = ();

  my @pk_guids = grep {
    $source->column_info($_)->{data_type}
    &&
    $source->column_info($_)->{data_type} =~ /^uniqueidentifier/i
  } @pk_cols;

  my @auto_guids = grep {
    $source->column_info($_)->{data_type}
    &&
    $source->column_info($_)->{data_type} =~ /^uniqueidentifier/i
    &&
    $source->column_info($_)->{auto_nextval}
  } grep { not exists $pk_cols{$_} } $source->columns;

  my @get_guids_for =
    grep { not exists $to_insert->{$_} } (@pk_guids, @auto_guids);

  my $updated_cols = {};

  for my $guid_col (@get_guids_for) {
    my ($new_guid) = $self->_get_dbh->selectrow_array('SELECT '.$self->_new_uuid);
    $updated_cols->{$guid_col} = $to_insert->{$guid_col} = $new_guid;
  }

  $updated_cols = { %$updated_cols, %{ $self->next::method(@_) } };

  return $updated_cols;
}

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;

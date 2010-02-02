package DBIx::Class::Storage::DBI::Sybase::ASA;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';
use List::Util ();

__PACKAGE__->mk_group_accessors(simple => qw/
  _identity
/);

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::ASA - Driver for Sybase SQL Anywhere

=head1 DESCRIPTION

This class implements autoincrements for Sybase SQL Anywhere and selects the
RowNumberOver limit implementation.

You need the C<DBD::SQLAnywhere> driver that comes with the SQL Anywhere
distribution, B<NOT> the one on CPAN. It is usually under a path such as:

    /opt/sqlanywhere11/sdk/perl

=cut

sub last_insert_id { shift->_identity }

sub insert {
  my $self = shift;
  my ($source, $to_insert) = @_;

  my $supplied_col_info = $self->_resolve_column_info($source, [keys %$to_insert]);

  my $is_identity_insert = (List::Util::first { $_->{is_auto_increment} } (values %$supplied_col_info) )
     ? 1
     : 0;

  if (not $is_identity_insert) {
    my ($identity_col) = grep $source->column_info($_)->{is_auto_increment},
      $source->primary_columns;
    my $dbh = $self->_get_dbh;
    my $table_name = $source->from;

    my ($identity) = $dbh->selectrow_array("SELECT GET_IDENTITY('$table_name')");

    $to_insert->{$identity_col} = $identity;

    $self->_identity($identity);
  }

  return $self->next::method(@_);
}

# stolen from DB2

sub _sql_maker_opts {
  my ( $self, $opts ) = @_;

  if ( $opts ) {
    $self->{_sql_maker_opts} = { %$opts };
  }

  return { limit_dialect => 'RowNumberOver', %{$self->{_sql_maker_opts}||{}} };
}

1;

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

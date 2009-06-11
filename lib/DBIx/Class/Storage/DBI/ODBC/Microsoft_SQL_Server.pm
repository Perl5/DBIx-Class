package DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MSSQL/;

sub insert_bulk {
  my ($self, $source, $cols, $data) = @_;
  next::method(@_);
}

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  my ($sql, $bind) = $self->next::method (@_);
  $sql .= ';SELECT SCOPE_IDENTITY()' if $op eq 'insert';

  my %identity_insert_tables;
  my $col_info = $self->_resolve_column_info($ident, [map $_->[0], @{$bind}]);

  foreach my $bound (@{$bind}) {
    my $col = $bound->[0];
    if ($col_info->{$col}->{is_auto_increment}) {
      my $table = $col_info->{$col}->{-result_source}->from;
      $identity_insert_tables{$table} = 1;
    }
  }

  my $identity_insert_on = join '', map { "SET IDENTITY_INSERT $_ ON; " } keys %identity_insert_tables;
  my $identity_insert_off = join '', map { "SET IDENTITY_INSERT $_ OFF; " } keys %identity_insert_tables;
  $sql = "$identity_insert_on $sql $identity_insert_off";

  return ($sql, $bind);
}

sub _execute {
    my $self = shift;
    my ($op) = @_;

    my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);
    if ($op eq 'insert') {
      $self->{_scope_identity} = $sth->fetchrow_array;
      $sth->finish;
    }

    return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id { shift->{_scope_identity} }

1;

__END__

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server - Support specific
to Microsoft SQL Server over ODBC

=head1 DESCRIPTION

This class implements support specific to Microsoft SQL Server over ODBC,
including auto-increment primary keys and SQL::Abstract::Limit dialect.  It
is loaded automatically by by DBIx::Class::Storage::DBI::ODBC when it
detects a MSSQL back-end.

=head1 IMPLEMENTATION NOTES

Microsoft SQL Server supports three methods of retrieving the IDENTITY
value for inserted row: IDENT_CURRENT, @@IDENTITY, and SCOPE_IDENTITY().
SCOPE_IDENTITY is used here because it is the safest.  However, it must
be called is the same execute statement, not just the same connection.

So, this implementation appends a SELECT SCOPE_IDENTITY() statement
onto each INSERT to accommodate that requirement.

=head1 AUTHORS

Marc Mims C<< <marc@questright.com> >>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim: sw=2 sts=2

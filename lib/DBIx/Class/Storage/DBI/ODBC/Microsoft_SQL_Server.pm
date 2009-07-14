package DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MSSQL/;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;
use List::Util();

__PACKAGE__->mk_group_accessors(simple => qw/
  _scope_identity _using_dynamic_cursors
/);

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server - Support specific
to Microsoft SQL Server over ODBC

=head1 DESCRIPTION

This class implements support specific to Microsoft SQL Server over ODBC,
including auto-increment primary keys and SQL::Abstract::Limit dialect.  It
is loaded automatically by by DBIx::Class::Storage::DBI::ODBC when it
detects a MSSQL back-end.

=head1 IMPLEMENTATION NOTES

Microsoft SQL Server supports three methods of retrieving the C<IDENTITY>
value for inserted row: C<IDENT_CURRENT>, C<@@IDENTITY>, and C<SCOPE_IDENTITY()>.
C<SCOPE_IDENTITY()> is used here because it is the safest.  However, it must
be called is the same execute statement, not just the same connection.

So, this implementation appends a C<SELECT SCOPE_IDENTITY()> statement
onto each C<INSERT> to accommodate that requirement.

If you use dynamic cursors with C<< odbc_cursortype => 2 >> or
L</on_connect_call_use_dynamic_cursors> then the less accurate
C<SELECT @@IDENTITY> is used instead.

=head1 MULTIPLE ACTIVE STATEMENTS

The following options are alternative ways to enable concurrent executing
statement support. Each has its own advantages and drawbacks.

=head2 connect_call_use_dynamic_cursors

Use as:

  on_connect_call => 'use_dynamic_cursors'

in your L<DBIx::Class::Storage::DBI/connect_info> as one way to enable multiple
concurrent statements.

Will add C<< odbc_cursortype => 2 >> to your DBI connection attributes. See
L<DBD::ODBC/odbc_cursortype> for more information.

This will not work with CODE ref connect_info's and will do nothing if you set
C<odbc_cursortype> yourself.

B<WARNING:> this will break C<SCOPE_IDENTITY()>, and C<SELECT @@IDENTITY> will
be used instead, which on SQL Server 2005 and later will return erroneous
results on tables which have an on insert trigger that inserts into another
table with an C<IDENTITY> column.

=cut

sub connect_call_use_dynamic_cursors {
  my $self = shift;

  if (ref($self->_dbi_connect_info->[0]) eq 'CODE') {
    croak 'cannot set DBI attributes on CODE ref connect_infos';
  }

  my $dbi_attrs = $self->_dbi_connect_info->[-1];
  $dbi_attrs ||= {};

  if (not exists $dbi_attrs->{odbc_cursortype}) {
    # turn on support for multiple concurrent statements, unless overridden
    $self->_dbi_connect_info->[-1] = { %$dbi_attrs, odbc_cursortype => 2 };
    # will take effect next connection
    $self->disconnect;
    $self->_using_dynamic_cursors(1);
  }
}

sub _rebless {
  no warnings 'uninitialized';
  my $self = shift;

  if (ref($self->_dbi_connect_info->[0]) ne 'CODE' &&
      $self->_dbi_connect_info->[-1]{odbc_cursortype} == 2) {
    $self->_using_dynamic_cursors(1);
    return;
  }

  $self->_using_dynamic_cursors(0);
}

sub insert_bulk {
  my $self = shift;
  my ($source, $cols, $data) = @_;

  my $identity_insert = 0;

  COLUMNS:
  foreach my $col (@{$cols}) {
    if ($source->column_info($col)->{is_auto_increment}) {
      $identity_insert = 1;
      last COLUMNS;
    }
  }

  if ($identity_insert) {
    my $table = $source->from;
    $self->_get_dbh->do("SET IDENTITY_INSERT $table ON");
  }

  $self->next::method(@_);

  if ($identity_insert) {
    my $table = $source->from;
    $self->_get_dbh->do("SET IDENTITY_INSERT $table OFF");
  }
}

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  my ($sql, $bind) = $self->next::method (@_);

  if ($op eq 'insert') {
    $sql .= ';SELECT SCOPE_IDENTITY()';

    my $col_info = $self->_resolve_column_info($ident, [map $_->[0], @{$bind}]);
    if (List::Util::first { $_->{is_auto_increment} } (values %$col_info) ) {

      my $table = $ident->from;
      my $identity_insert_on = "SET IDENTITY_INSERT $table ON";
      my $identity_insert_off = "SET IDENTITY_INSERT $table OFF";
      $sql = "$identity_insert_on; $sql; $identity_insert_off";
    }
  }

  return ($sql, $bind);
}

sub _execute {
    my $self = shift;
    my ($op) = @_;

    my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);
    if ($op eq 'insert') {
      my ($identity) = $sth->fetchrow_array;
      $sth->finish;

      if ((not defined $identity) && $self->_using_dynamic_cursors) {
        ($identity) = $self->_dbh->selectrow_array('select @@identity');
      }

      $self->_scope_identity($identity);
    }

    return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id { shift->_scope_identity() }

1;

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

# vim: sw=2 sts=2

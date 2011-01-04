package DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MSSQL/;
use mro 'c3';
use Scalar::Util 'reftype';
use Try::Tiny;
use Carp::Clan qw/^DBIx::Class/;
use namespace::clean;

__PACKAGE__->mk_group_accessors(simple => qw/
  _using_dynamic_cursors
/);

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server - Support specific
to Microsoft SQL Server over ODBC

=head1 DESCRIPTION

This class implements support specific to Microsoft SQL Server over ODBC.  It is
loaded automatically by by DBIx::Class::Storage::DBI::ODBC when it detects a
MSSQL back-end.

Most of the functionality is provided from the superclass
L<DBIx::Class::Storage::DBI::MSSQL>.

=head1 MULTIPLE ACTIVE STATEMENTS

The following options are alternative ways to enable concurrent executing
statement support. Each has its own advantages and drawbacks and works on
different platforms. Read each section carefully.

In order of preference, they are:

=over 8

=item * L</connect_call_use_mars>

=item * L</connect_call_use_dynamic_cursors>

=item * L</connect_call_use_server_cursors>

=back

=head1 METHODS

=head2 connect_call_use_mars

Use as:

  on_connect_call => 'use_mars'

Use to enable a feature of SQL Server 2005 and later, "Multiple Active Result
Sets". See L<DBD::ODBC::FAQ/Does DBD::ODBC support Multiple Active Statements?>
for more information.

This does not work on FreeTDS drivers at the time of this writing, and only
works with the Native Client, later versions of the Windows MS ODBC driver, and
the Easysoft driver.

=cut

sub connect_call_use_mars {
  my $self = shift;

  my $dsn = $self->_dbi_connect_info->[0];

  if (ref($dsn) eq 'CODE') {
    $self->throw_exception('cannot change the DBI DSN on a CODE ref connect_info');
  }

  if ($dsn !~ /MARS_Connection=/) {
    if ($self->using_freetds) {
      $self->throw_exception('FreeTDS does not support MARS at the time of '
                            .'writing.');
    }

    if (exists $self->_server_info->{normalized_dbms_version} &&
               $self->_server_info->{normalized_dbms_version} < 9) {
      $self->throw_exception('SQL Server 2005 or later required to use MARS.');
    }

    if (my ($data_source) = $dsn =~ /^dbi:ODBC:([\w-]+)\z/i) { # prefix with DSN
      warn "Bare DSN in ODBC connect string, rewriting to DSN=$data_source\n";
      $dsn = "dbi:ODBC:DSN=$data_source";
    }

    $self->_dbi_connect_info->[0] = "$dsn;MARS_Connection=Yes";
    $self->disconnect;
    $self->ensure_connected;
  }
}

sub connect_call_use_MARS {
  carp "'connect_call_use_MARS' has been deprecated, use "
      ."'connect_call_use_mars' instead.";
  shift->connect_call_use_mars(@_)
}

=head2 connect_call_use_dynamic_cursors

Use as:

  on_connect_call => 'use_dynamic_cursors'

in your L<connect_info|DBIx::Class::Storage::DBI/connect_info> as one way to enable multiple
concurrent statements.

Will add C<< odbc_cursortype => 2 >> to your DBI connection attributes. See
L<DBD::ODBC/odbc_cursortype> for more information.

Alternatively, you can add it yourself and dynamic cursor support will be
automatically enabled.

If you're using FreeTDS, C<tds_version> must be set to at least C<8.0>.

This will not work with CODE ref connect_info's.

B<WARNING:> this will break C<SCOPE_IDENTITY()>, and C<SELECT @@IDENTITY> will
be used instead, which on SQL Server 2005 and later will return erroneous
results on tables which have an on insert trigger that inserts into another
table with an C<IDENTITY> column.

=cut

sub connect_call_use_dynamic_cursors {
  my $self = shift;

  if (ref($self->_dbi_connect_info->[0]) eq 'CODE') {
    $self->throw_exception ('Cannot set DBI attributes on a CODE ref connect_info');
  }

  my $dbi_attrs = $self->_dbi_connect_info->[-1];

  unless (ref $dbi_attrs eq 'HASH') {
    $dbi_attrs = {};
    push @{ $self->_dbi_connect_info }, $dbi_attrs;
  }

  if (not exists $dbi_attrs->{odbc_cursortype}) {
    # turn on support for multiple concurrent statements, unless overridden
    $dbi_attrs->{odbc_cursortype} = 2;
    $self->disconnect; # resetting dbi attrs, so have to reconnect
    $self->ensure_connected;
    $self->_set_dynamic_cursors;
  }
}

sub _set_dynamic_cursors {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  try {
    local $dbh->{RaiseError} = 1;
    local $dbh->{PrintError} = 0;
    $dbh->do('SELECT @@IDENTITY');
  } catch {
    $self->throw_exception (<<'EOF');

Your drivers do not seem to support dynamic cursors (odbc_cursortype => 2),
if you're using FreeTDS, make sure to set tds_version to 8.0 or greater.
EOF
  };

  $self->_using_dynamic_cursors(1);
  $self->_identity_method('@@identity');
}

sub _init {
  my $self = shift;

  if (
    ref($self->_dbi_connect_info->[0]) ne 'CODE'
      &&
    ref ($self->_dbi_connect_info->[-1]) eq 'HASH'
      &&
    ($self->_dbi_connect_info->[-1]{odbc_cursortype} || 0) > 1
  ) {
    $self->_set_dynamic_cursors;
  }
  else {
    $self->_using_dynamic_cursors(0);
  }
}

=head2 connect_call_use_server_cursors

Use as:

  on_connect_call => 'use_server_cursors'

May allow multiple active select statements. See
L<DBD::ODBC/odbc_SQL_ROWSET_SIZE> for more information.

Takes an optional parameter for the value to set the attribute to, default is
C<2>.

B<WARNING>: this does not work on all versions of SQL Server, and may lock up
your database!

At the time of writing, this option only works on Microsoft's Windows drivers,
later versions of the ODBC driver and the Native Client driver.

=cut

sub connect_call_use_server_cursors {
  my $self            = shift;
  my $sql_rowset_size = shift || 2;

  if ($^O !~ /win32|cygwin/i) {
    $self->throw_exception('Server cursors only work on Windows platforms at '
                          .'the time of writing.');
  }

  $self->_get_dbh->{odbc_SQL_ROWSET_SIZE} = $sql_rowset_size;
}

=head2 using_freetds

Tries to determine, to the best of our ability, whether or not you are using the
FreeTDS driver with L<DBD::ODBC>.

=cut

sub using_freetds {
  my $self = shift;

  my $dsn = $self->_dbi_connect_info->[0];

  $dsn = '' if ref $dsn eq 'CODE';

  my $dbh = $self->_get_dbh;

  return 1 if $dsn =~ /driver=FreeTDS/i
              || (try { $dbh->get_info(6) }||'') =~ /tdsodbc/i;

  return 0;
}

1;

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim: sw=2 sts=2

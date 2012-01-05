package DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server;

use strict;
use warnings;

use base qw/
  DBIx::Class::Storage::DBI::Sybase
  DBIx::Class::Storage::DBI::MSSQL
/;
use mro 'c3';

use DBIx::Class::Carp;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server - Support for Microsoft
SQL Server via DBD::Sybase

=head1 SYNOPSIS

This subclass supports MSSQL server connections via L<DBD::Sybase>.

=head1 DESCRIPTION

This driver tries to determine whether your version of L<DBD::Sybase> and
supporting libraries (usually FreeTDS) support using placeholders, if not the
storage will be reblessed to
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::NoBindVars>.

The MSSQL specific functionality is provided by
L<DBIx::Class::Storage::DBI::MSSQL>.

=head1 METHODS

=cut

__PACKAGE__->datetime_parser_type(
  'DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::DateTime::Format'
);

sub _rebless {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  return if ref $self ne __PACKAGE__;
  if (not $self->_use_typeless_placeholders) {
    carp_once <<'EOF' unless $ENV{DBIC_MSSQL_FREETDS_LOWVER_NOWARN};
Placeholders do not seem to be supported in your configuration of
DBD::Sybase/FreeTDS.

This means you are taking a large performance hit, as caching of prepared
statements is disabled.

Make sure to configure your server with "tds version" of 8.0 or 7.0 in
/etc/freetds/freetds.conf .

To turn off this warning, set the DBIC_MSSQL_FREETDS_LOWVER_NOWARN environment
variable.
EOF
    require
      DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::NoBindVars;
    bless $self,
      'DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::NoBindVars';
    $self->_rebless;
  }
}

# invoked only if DBD::Sybase is compiled against FreeTDS
sub _set_autocommit_stmt {
  my ($self, $on) = @_;

  return 'SET IMPLICIT_TRANSACTIONS ' . ($on ? 'OFF' : 'ON');
}

sub _get_server_version {
  my $self = shift;

  my $product_version = $self->_get_dbh->selectrow_hashref('master.dbo.xp_msver ProductVersion');

  if ((my $version = $product_version->{Character_Value}) =~ /^(\d+)\./) {
    return $version;
  }
  else {
    $self->throw_exception(
      "MSSQL Version Retrieval Failed, Your ProductVersion's Character_Value is missing or malformed!"
    );
  }
}

=head2 connect_call_datetime_setup

Used as:

  on_connect_call => 'datetime_setup'

In L<connect_info|DBIx::Class::Storage::DBI/connect_info> to set:

  $dbh->syb_date_fmt('ISO_strict'); # output fmt: 2004-08-21T14:36:48.080Z

On connection for use with L<DBIx::Class::InflateColumn::DateTime>

This works for both C<DATETIME> and C<SMALLDATETIME> columns, although
C<SMALLDATETIME> columns only have minute precision.

=cut

sub connect_call_datetime_setup {
  my $self = shift;
  my $dbh = $self->_get_dbh;

  if ($dbh->can('syb_date_fmt')) {
    # amazingly, this works with FreeTDS
    $dbh->syb_date_fmt('ISO_strict');
  }
  else{
    carp_once
      'Your DBD::Sybase is too old to support '
    . 'DBIx::Class::InflateColumn::DateTime, please upgrade!';
  }
}


package # hide from PAUSE
  DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::DateTime::Format;

my $datetime_parse_format  = '%Y-%m-%dT%H:%M:%S.%3NZ';
my $datetime_format_format = '%Y-%m-%d %H:%M:%S.%3N'; # %F %T

my ($datetime_parser, $datetime_formatter);

sub parse_datetime {
  shift;
  require DateTime::Format::Strptime;
  $datetime_parser ||= DateTime::Format::Strptime->new(
    pattern  => $datetime_parse_format,
    on_error => 'croak',
  );
  return $datetime_parser->parse_datetime(shift);
}

sub format_datetime {
  shift;
  require DateTime::Format::Strptime;
  $datetime_formatter ||= DateTime::Format::Strptime->new(
    pattern  => $datetime_format_format,
    on_error => 'croak',
  );
  return $datetime_formatter->format_datetime(shift);
}

1;

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

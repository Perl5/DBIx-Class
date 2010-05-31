package DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server;

use strict;
use warnings;

use base qw/
  DBIx::Class::Storage::DBI::Sybase
  DBIx::Class::Storage::DBI::MSSQL
/;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;

sub _rebless {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  return if ref $self ne __PACKAGE__;

  if (not $self->_typeless_placeholders_supported) {
    require
      DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::NoBindVars;
    bless $self,
      'DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::NoBindVars';
    $self->_rebless;
  }
}

sub _run_connection_actions {
  my $self = shift;

  # LongReadLen doesn't work with MSSQL through DBD::Sybase, and the default is
  # huge on some versions of SQL server and can cause memory problems, so we
  # fix it up here (see ::DBI::Sybase.pm)
  $self->set_textsize;

  $self->next::method(@_);
}

sub _dbh_begin_work {
  my $self = shift;

  $self->_get_dbh->do('BEGIN TRAN');
}

sub _dbh_commit {
  my $self = shift;
  my $dbh  = $self->_dbh
    or $self->throw_exception('cannot COMMIT on a disconnected handle');
  $dbh->do('COMMIT');
}

sub _dbh_rollback {
  my $self = shift;
  my $dbh  = $self->_dbh
    or $self->throw_exception('cannot ROLLBACK on a disconnected handle');
  $dbh->do('ROLLBACK');
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

{
  my $old_dbd_warned = 0;

  sub connect_call_datetime_setup {
    my $self = shift;
    my $dbh = $self->_get_dbh;

    if ($dbh->can('syb_date_fmt')) {
      # amazingly, this works with FreeTDS
      $dbh->syb_date_fmt('ISO_strict');
    } elsif (not $old_dbd_warned) {
      carp "Your DBD::Sybase is too old to support ".
      "DBIx::Class::InflateColumn::DateTime, please upgrade!";
      $old_dbd_warned = 1;
    }
  }
}

sub datetime_parser_type {
  'DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server::DateTime::Format'
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

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

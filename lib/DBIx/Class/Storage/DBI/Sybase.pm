package DBIx::Class::Storage::DBI::Sybase;

use strict;
use warnings;

use base qw/
    DBIx::Class::Storage::DBI::Sybase::Base
    DBIx::Class::Storage::DBI
/;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase - Storage::DBI subclass for Sybase

=head1 SYNOPSIS

This subclass supports L<DBD::Sybase> for real Sybase databases.  If you are
using an MSSQL database via L<DBD::Sybase>, your storage will be reblessed to
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>.

=head1 DESCRIPTION

If your version of Sybase does not support placeholders, then your storage
will be reblessed to L<DBIx::Class::Storage::DBI::Sybase::NoBindVars>. You can
also enable that driver explicitly, see the documentation for more details.

With this driver there is unfortunately no way to get the C<last_insert_id>
without doing a C<select max(col)>.

But your queries will be cached.

A recommended L<DBIx::Class::Storage::DBI/connect_info> settings:

  on_connect_call => [['datetime_setup'], [blob_setup => log_on_update => 0]]

=head1 METHODS

=cut

__PACKAGE__->mk_group_accessors('simple' =>
    qw/_blob_log_on_update/
);

sub _rebless {
  my $self = shift;

  if (ref($self) eq 'DBIx::Class::Storage::DBI::Sybase') {
    my $dbtype = eval {
      @{$self->dbh->selectrow_arrayref(qq{sp_server_info \@attribute_id=1})}[2]
    } || '';

    my $exception = $@;
    $dbtype =~ s/\W/_/gi;
    my $subclass = "DBIx::Class::Storage::DBI::Sybase::${dbtype}";

    if (!$exception && $dbtype && $self->load_optional_class($subclass)) {
      bless $self, $subclass;
      $self->_rebless;
    } else {
      # real Sybase
      if (not $self->dbh->{syb_dynamic_supported}) {
        $self->ensure_class_loaded('DBIx::Class::Storage::DBI::Sybase::NoBindVars');
        bless $self, 'DBIx::Class::Storage::DBI::Sybase::NoBindVars';
        $self->_rebless;
      }
      $self->_set_maxConnect;
    }
  }
}

sub _set_maxConnect {
  my $self = shift;

  my $dsn = $self->_dbi_connect_info->[0];

  return if ref($dsn) eq 'CODE';

  if ($dsn !~ /maxConnect=/) {
    $self->_dbi_connect_info->[0] = "$dsn;maxConnect=256";
    my $connected = defined $self->_dbh;
    $self->disconnect;
    $self->ensure_connected if $connected;
  }
}

=head2 connect_call_blob_setup

Used as:

  on_connect_call => [ [ blob_setup => log_on_update => 0 ] ]

Does C<< $dbh->{syb_binary_images} = 1; >> to return C<IMAGE> data as raw binary
instead of as a hex string.

Recommended.

Also sets the C<log_on_update> value for blob write operations. The default is
C<1>, but C<0> is better if your database is configured for it.

See
L<DBD::Sybase/Handling_IMAGE/TEXT_data_with_syb_ct_get_data()/syb_ct_send_data()>.

=cut

sub connect_call_blob_setup {
  my $self = shift;
  my %args = @_;
  my $dbh = $self->_dbh;
  $dbh->{syb_binary_images} = 1;

  $self->_blob_log_on_update($args{log_on_update})
    if exists $args{log_on_update};
}

sub _is_lob_type {
  my $self = shift;
  shift =~ /(?:text|image|lob|bytea|binary)/i;
}

sub insert {
  my ($self, $source, $to_insert) = splice @_, 0, 3;

  my $blob_cols = $self->_remove_blob_cols($source, $to_insert);

  my $updated_cols = $self->next::method($source, $to_insert, @_);

  $self->_update_blobs($source, $blob_cols, $to_insert) if %$blob_cols;

  return $updated_cols;
}

#sub update {
#  my ($self, $source) = splice @_, 0, 2;
#  my ($fields)        = @_;
#
#  my $blob_cols = $self->_remove_blob_cols($source, $fields);
#
#  my @res = 1;
#
#  if (%$fields) {
#    if (wantarray) {
#      @res    = $self->next::method($source, @_);
#    } else {
#      $res[0] = $self->next::method($source, @_);
#    }
#  }
#
#  $self->_update_blobs($source, $blob_cols, $fields) if %$blob_cols;
#
#  return wantarray ? @res : $res[0];
#}

sub _remove_blob_cols {
  my ($self, $source, $fields) = @_;

  my %blob_cols;

  for my $col (keys %$fields) {
    if ($self->_is_lob_type($source->column_info($col)->{data_type})) {
      $blob_cols{$col} = delete $fields->{$col};
      $fields->{$col} = \"''";
    }
  }

  return \%blob_cols;
}

sub _update_blobs {
  my ($self, $source, $blob_cols, $inserted) = @_;
  my $dbh = $self->dbh;

  my $table = $source->from;

  my %inserted = %$inserted;
  my (@primary_cols) = $source->primary_columns;

  croak "Cannot update TEXT/IMAGE column(s) without a primary key"
    unless @primary_cols;

  if ((grep { defined $inserted{$_} } @primary_cols) != @primary_cols) {
    if (@primary_cols == 1) {
      my $col = $primary_cols[0];
      $inserted{$col} = $self->last_insert_id($source, $col);
    } else {
      croak "Cannot update TEXT/IMAGE column(s) without primary key values";
    }
  }

  for my $col (keys %$blob_cols) {
    my $blob = $blob_cols->{$col};
    my $sth;

    if (not $self->isa('DBIx::Class::Storage::DBI::NoBindVars')) {
      my $search_cond = join ',' => map "$_ = ?", @primary_cols;

      $sth = $self->sth(
        "select $col from $table where $search_cond"
      );
      $sth->execute(map $inserted{$_}, @primary_cols);
    } else {
      my $search_cond = join ',' => map "$_ = $inserted{$_}", @primary_cols;

      $sth = $dbh->prepare(
        "select $col from $table where $search_cond"
      );
      $sth->execute;
    }

    eval {
      while ($sth->fetch) {
        $sth->func('CS_GET', 1, 'ct_data_info') or die $sth->errstr;
      }
      $sth->func('ct_prepare_send') or die $sth->errstr;

      my $log_on_update = $self->_blob_log_on_update;
      $log_on_update    = 1 if not defined $log_on_update;

      $sth->func('CS_SET', 1, {
        total_txtlen => length($blob),
        log_on_update => $log_on_update
      }, 'ct_data_info') or die $sth->errstr;

      $sth->func($blob, length($blob), 'ct_send_data') or die $sth->errstr;

      $sth->func('ct_finish_send') or die $sth->errstr;
    };
    my $exception = $@;
    $sth->finish;
    croak $exception if $exception;
  }
}

=head2 connect_call_datetime_setup

Used as:

  on_connect_call => 'datetime_setup'

In L<DBIx::Class::Storage::DBI/connect_info> to set:

  $dbh->syb_date_fmt('ISO_strict'); # output fmt: 2004-08-21T14:36:48.080Z
  $dbh->do('set dateformat mdy');   # input fmt:  08/13/1979 18:08:55.080

On connection for use with L<DBIx::Class::InflateColumn::DateTime>, using
L<DateTime::Format::Sybase>, which you will need to install.

This works for both C<DATETIME> and C<SMALLDATETIME> columns, although
C<SMALLDATETIME> columns only have minute precision.

=cut

{
  my $old_dbd_warned = 0;

  sub connect_call_datetime_setup {
    my $self = shift;
    my $dbh = $self->_dbh;

    if ($dbh->can('syb_date_fmt')) {
      $dbh->syb_date_fmt('ISO_strict');
    } elsif (not $old_dbd_warned) {
      carp "Your DBD::Sybase is too old to support ".
      "DBIx::Class::InflateColumn::DateTime, please upgrade!";
      $old_dbd_warned = 1;
    }

    $dbh->do('set dateformat mdy');

    1;
  }
}

sub datetime_parser_type { "DateTime::Format::Sybase" }

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;

  # sorry, there's no other way!
  my $sth = $dbh->prepare_cached("select max($col) from ".$source->from);
  return ($dbh->selectrow_array($sth))[0];
}

1;

=head1 MAXIMUM CONNECTIONS

L<DBD::Sybase> makes separate connections to the server for active statements in
the background. By default the number of such connections is limited to 25, on
both the client side and the server side.

This is a bit too low, so on connection the clientside setting is set to C<256>
(see L<DBD::Sybase/maxConnect>.) You can override it to whatever setting you
like in the DSN.

See
L<http://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.help.ase_15.0.sag1/html/sag1/sag1272.htm>
for information on changing the setting on the server side.

=head1 DATES

See L</connect_call_datetime_setup> to setup date formats
for L<DBIx::Class::InflateColumn::DateTime>.

=head1 IMAGE AND TEXT COLUMNS

See L</connect_call_blob_setup> for a L<DBIx::Class::Storage::DBI/connect_info>
setting you need to work with C<IMAGE> columns.

Due to limitations in L<DBD::Sybase> and this driver, it is only possible to
select one C<TEXT> or C<IMAGE> column at a time.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

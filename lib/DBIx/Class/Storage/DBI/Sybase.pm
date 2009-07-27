package DBIx::Class::Storage::DBI::Sybase;

use strict;
use warnings;

use base qw/
    DBIx::Class::Storage::DBI::Sybase::Base
    DBIx::Class::Storage::DBI
/;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;
use List::Util ();

__PACKAGE__->mk_group_accessors('simple' =>
    qw/_identity _blob_log_on_update _auto_cast _insert_txn/
);

=head1 NAME

DBIx::Class::Storage::DBI::Sybase - Sybase support for DBIx::Class

=head1 SYNOPSIS

This subclass supports L<DBD::Sybase> for real Sybase databases.  If you are
using an MSSQL database via L<DBD::Sybase>, your storage will be reblessed to
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>.

=head1 DESCRIPTION

If your version of Sybase does not support placeholders, then your storage
will be reblessed to L<DBIx::Class::Storage::DBI::Sybase::NoBindVars>. You can
also enable that driver explicitly, see the documentation for more details.

With this driver there is unfortunately no way to get the C<last_insert_id>
without doing a C<SELECT MAX(col)>.

But your queries will be cached.

You need a version of L<DBD::Sybase> compiled with the Sybase OpenClient
libraries, B<NOT> FreeTDS, for placeholder support. Otherwise your storage will
be automatically reblessed into C<::NoBindVars>.

A recommended L<DBIx::Class::Storage::DBI/connect_info> setting:

  on_connect_call => [['datetime_setup'], ['blob_setup', log_on_update => 0]]

=head1 METHODS

=cut

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
    } else { # real Sybase
      my $no_bind_vars = 'DBIx::Class::Storage::DBI::Sybase::NoBindVars';

# This is reset to 0 in ::NoBindVars, only necessary because we use max(col) to
# get the identity.
      $self->_insert_txn(1);

      if ($self->_using_freetds) {
        carp <<'EOF' unless $ENV{DBIC_SYBASE_FREETDS_NOWARN};

You are using FreeTDS with Sybase.

We will do our best to support this configuration, but please consider this
support experimental.

TEXT/IMAGE columns will definitely not work.

You are encouraged to recompile DBD::Sybase with the Sybase OpenClient libraries
instead.

See perldoc DBIx::Class::Storage::DBI::Sybase for more details.

To turn off this warning set the DBIC_SYBASE_FREETDS_NOWARN environment
variable.
EOF
        if (not $self->_placeholders_with_type_conversion_supported) {
          if ($self->_placeholders_supported) {
            $self->_auto_cast(1);
          } else {
            $self->ensure_class_loaded($no_bind_vars);
            bless $self, $no_bind_vars;
            $self->_rebless;
          }
        }
      }

      if (not $self->dbh->{syb_dynamic_supported}) {
        $self->ensure_class_loaded($no_bind_vars);
        bless $self, $no_bind_vars;
        $self->_rebless;
      }
 
      $self->_set_max_connect(256);
    }
  }
}

# Make sure we have CHAINED mode turned on if AutoCommit is off in non-FreeTDS
# DBD::Sybase (since we don't know how DBD::Sybase was compiled.) If however
# we're using FreeTDS, CHAINED mode turns on an implicit transaction which we
# only want when AutoCommit is off.
sub _populate_dbh {
  my $self = shift;

  $self->next::method(@_);

  if (not $self->_using_freetds) {
    $self->_dbh->{syb_chained_txn} = 1;
  } else {
    if ($self->_dbh_autocommit) {
      $self->_dbh->do('SET CHAINED OFF');
    } else {
      $self->_dbh->do('SET CHAINED ON');
    }
  }
}

=head2 connect_call_blob_setup

Used as:

  on_connect_call => [ [ 'blob_setup', log_on_update => 0 ] ]

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
  my $type = shift;
  $type && $type =~ /(?:text|image|lob|bytea|binary|memo)/i;
}

# The select-piggybacking-on-insert trick stolen from odbc/mssql
sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  my ($sql, $bind) = $self->next::method (@_);

# Some combinations of FreeTDS and Sybase throw implicit conversion errors for
# all placeeholders, so we convert them into CASTs here.
# Based on code in ::DBI::NoBindVars .
#
# If we're using ::NoBindVars, there are no binds by this point so this code
# gets skippeed.
  if ($self->_auto_cast && @$bind) {
    my $new_sql;
    my @sql_part = split /\?/, $sql;
    my $col_info = $self->_resolve_column_info($ident,[ map $_->[0], @$bind ]);

    foreach my $bound (@$bind) {
      my $col = $bound->[0];
      my $syb_type = $self->_syb_base_type($col_info->{$col}{data_type});

      foreach my $data (@{$bound}[1..$#$bound]) {
        $new_sql .= shift(@sql_part) .
          ($syb_type ? "CAST(? AS $syb_type)" : '?');
      }
    }
    $new_sql .= join '', @sql_part;
    $sql = $new_sql;
  }

  if ($op eq 'insert') {
    my $table = $ident->from;

    my $bind_info = $self->_resolve_column_info(
      $ident, [map $_->[0], @{$bind}]
    );
    my $identity_col =
List::Util::first { $bind_info->{$_}{is_auto_increment} } (keys %$bind_info);

    if ($identity_col) {
      $sql =
"SET IDENTITY_INSERT $table ON\n" .
"$sql\n" .
"SET IDENTITY_INSERT $table OFF"
    } else {
      $identity_col = List::Util::first {
        $ident->column_info($_)->{is_auto_increment}
      } $ident->columns;
    }

    if ($identity_col) {
      $sql =
        "$sql\n" .
        $self->_fetch_identity_sql($ident, $identity_col);
    }
  }

  return ($sql, $bind);
}

# Stolen from SQLT, with some modifications. This will likely change when the
# SQLT Sybase stuff is redone/fixed-up.
my %TYPE_MAPPING  = (
    number    => 'numeric',
    money     => 'money',
    varchar   => 'varchar',
    varchar2  => 'varchar',
    timestamp => 'datetime',
    text      => 'varchar',
    real      => 'double precision',
    comment   => 'text',
    bit       => 'bit',
    tinyint   => 'smallint',
    float     => 'double precision',
    serial    => 'numeric',
    bigserial => 'numeric',
    boolean   => 'varchar',
    long      => 'varchar',
);

sub _syb_base_type {
  my ($self, $type) = @_;

  $type = lc $type;
  $type =~ s/ identity//;

  return uc($TYPE_MAPPING{$type} || $type);
}

sub _fetch_identity_sql {
  my ($self, $source, $col) = @_;

  return "SELECT MAX($col) FROM ".$source->from;
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);

  if ($op eq 'insert') {
    $self->_identity($sth->fetchrow_array);
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id { shift->_identity }

# override to handle TEXT/IMAGE and to do a transaction if necessary
sub insert {
  my ($self, $source, $to_insert) = splice @_, 0, 3;
  my $dbh = $self->_dbh;

  my $blob_cols = $self->_remove_blob_cols($source, $to_insert);

# We have to do the insert in a transaction to avoid race conditions with the
# SELECT MAX(COL) identity method used when placeholders are enabled.
  my $updated_cols = do {
    if ($self->_insert_txn && (not $self->{transaction_depth})) {
      my $args = \@_;
      my $method = $self->next::can;
      $self->txn_do(
        sub { $self->$method($source, $to_insert, @$args) }
      );
    } else {
      $self->next::method($source, $to_insert, @_);
    }
  };

  $self->_insert_blobs($source, $blob_cols, $to_insert) if %$blob_cols;

  return $updated_cols;
}

sub update {
  my ($self, $source)  = splice @_, 0, 2;
  my ($fields, $where) = @_;
  my $wantarray        = wantarray;

  my $blob_cols = $self->_remove_blob_cols($source, $fields);

  my @res;
  if ($wantarray) {
    @res    = $self->next::method($source, @_);
  } else {
    $res[0] = $self->next::method($source, @_);
  }

  $self->_update_blobs($source, $blob_cols, $where) if %$blob_cols;

  return $wantarray ? @res : $res[0];
}

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
  my ($self, $source, $blob_cols, $where) = @_;

  my (@primary_cols) = $source->primary_columns;

  croak "Cannot update TEXT/IMAGE column(s) without a primary key"
    unless @primary_cols;

# check if we're updating a single row by PK
  my $pk_cols_in_where = 0;
  for my $col (@primary_cols) {
    $pk_cols_in_where++ if defined $where->{$col};
  }
  my @rows;

  if ($pk_cols_in_where == @primary_cols) {
    my %row_to_update;
    @row_to_update{@primary_cols} = @{$where}{@primary_cols};
    @rows = \%row_to_update;
  } else {
    my $rs = $source->resultset->search(
      $where,
      {
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        select => \@primary_cols
      }
    );
    @rows = $rs->all; # statement must finish
  }

  for my $row (@rows) {
    $self->_insert_blobs($source, $blob_cols, $row);
  }
}

sub _insert_blobs {
  my ($self, $source, $blob_cols, $row) = @_;
  my $dbh = $self->dbh;

  my $table = $source->from;

  my %row = %$row;
  my (@primary_cols) = $source->primary_columns;

  croak "Cannot update TEXT/IMAGE column(s) without a primary key"
    unless @primary_cols;

  if ((grep { defined $row{$_} } @primary_cols) != @primary_cols) {
    if (@primary_cols == 1) {
      my $col = $primary_cols[0];
      $row{$col} = $self->last_insert_id($source, $col);
    } else {
      croak "Cannot update TEXT/IMAGE column(s) without primary key values";
    }
  }

  for my $col (keys %$blob_cols) {
    my $blob = $blob_cols->{$col};
    my $sth;

    my %where = map { ($_, $row{$_}) } @primary_cols;
    my $cursor = $source->resultset->search(\%where, {
      select => [$col]
    })->cursor;
    $cursor->next;
    $sth = $cursor->sth;

    eval {
      do {
        $sth->func('CS_GET', 1, 'ct_data_info') or die $sth->errstr;
      } while $sth->fetch;

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
    $sth->finish if $sth;
    if ($exception) {
      if ($self->_using_freetds) {
        croak
"TEXT/IMAGE operation failed, probably because you're using FreeTDS: " .
$exception;
      } else {
        croak $exception;
      }
    }
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

# ->begin_work and such have no effect with FreeTDS

sub _dbh_begin_work {
  my $self = shift;
  if (not $self->_using_freetds) {
    return $self->next::method(@_);
  } else {
    $self->dbh->do('BEGIN TRAN');
  }
}

sub _dbh_commit {
  my $self = shift;
  if (not $self->_using_freetds) {
    return $self->next::method(@_);
  } else {
    $self->_dbh->do('COMMIT');
  }
}

sub _dbh_rollback {
  my $self = shift;
  if (not $self->_using_freetds) {
    return $self->next::method(@_);
  } else {
    $self->_dbh->do('ROLLBACK');
  }
}

# savepoint support using ASE syntax

sub _svp_begin {
  my ($self, $name) = @_;

  $self->dbh->do("SAVE TRANSACTION $name");
}

# A new SAVE TRANSACTION with the same name releases the previous one.
sub _svp_release { 1 }

sub _svp_rollback {
  my ($self, $name) = @_;

  $self->dbh->do("ROLLBACK TRANSACTION $name");
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

L<DBD::Sybase> compiled with FreeTDS will B<NOT> allow you to insert or update
C<TEXT/IMAGE> columns.

C<< $dbh->{LongReadLen} >> will also not work with FreeTDS use:

  $schema->storage->dbh->do("SET TEXTSIZE <bytes>")

instead.

See L</connect_call_blob_setup> for a L<DBIx::Class::Storage::DBI/connect_info>
setting you need to work with C<IMAGE> columns.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

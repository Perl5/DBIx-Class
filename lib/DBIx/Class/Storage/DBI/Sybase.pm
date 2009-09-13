package DBIx::Class::Storage::DBI::Sybase;

use strict;
use warnings;

use base qw/
    DBIx::Class::Storage::DBI::Sybase::Common
    DBIx::Class::Storage::DBI::AutoCast
/;
use mro 'c3';
use Carp::Clan qw/^DBIx::Class/;
use List::Util ();
use Sub::Name ();

__PACKAGE__->mk_group_accessors('simple' =>
    qw/_identity _blob_log_on_update _insert_storage _identity_method/
);

my @delegate_to_insert_storage = qw/
  disconnect _connect_info _sql_maker _sql_maker_opts disable_sth_caching
  auto_savepoint unsafe cursor_class debug debugobj schema
/;

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
without doing a C<SELECT MAX(col)>. This is done safely in a transaction
(locking the table.) See L</INSERTS WITH PLACEHOLDERS>.

A recommended L<DBIx::Class::Storage::DBI/connect_info> setting:

  on_connect_call => [['datetime_setup'], ['blob_setup', log_on_update => 0]]

=head1 METHODS

=cut

sub _rebless {
  my $self = shift;

  if (ref($self) eq 'DBIx::Class::Storage::DBI::Sybase') {
    my $dbtype = eval {
      @{$self->_get_dbh->selectrow_arrayref(qq{sp_server_info \@attribute_id=1})}[2]
    } || '';

    my $exception = $@;
    $dbtype =~ s/\W/_/gi;
    my $subclass = "DBIx::Class::Storage::DBI::Sybase::${dbtype}";

    if (!$exception && $dbtype && $self->load_optional_class($subclass)) {
      bless $self, $subclass;
      $self->_rebless;
    } else { # real Sybase
      my $no_bind_vars = 'DBIx::Class::Storage::DBI::Sybase::NoBindVars';

      if ($self->using_freetds) {
        carp <<'EOF' unless $ENV{DBIC_SYBASE_FREETDS_NOWARN};

You are using FreeTDS with Sybase.

We will do our best to support this configuration, but please consider this
support experimental.

TEXT/IMAGE columns will definitely not work.

You are encouraged to recompile DBD::Sybase with the Sybase Open Client libraries
instead.

See perldoc DBIx::Class::Storage::DBI::Sybase for more details.

To turn off this warning set the DBIC_SYBASE_FREETDS_NOWARN environment
variable.
EOF
        if (not $self->_typeless_placeholders_supported) {
          if ($self->_placeholders_supported) {
            $self->auto_cast(1);
          } else {
            $self->ensure_class_loaded($no_bind_vars);
            bless $self, $no_bind_vars;
            $self->_rebless;
          }
        }
      }
      elsif (not $self->_get_dbh->{syb_dynamic_supported}) {
        # not necessarily FreeTDS, but no placeholders nevertheless
        $self->ensure_class_loaded($no_bind_vars);
        bless $self, $no_bind_vars;
        $self->_rebless;
      } elsif (not $self->_typeless_placeholders_supported) {
# this is highly unlikely, but we check just in case
        $self->auto_cast(1);
      }
    }
  }
}

sub _init {
  my $self = shift;
  $self->_set_max_connect(256);

  # based on LongReadLen in connect_info
  $self->set_textsize if $self->using_freetds;

# create storage for insert transactions
  $self->_insert_storage((ref $self)->new);
  $self->_insert_storage->connect_info($self->connect_info);

  $self->_insert_storage->set_textsize if $self->using_freetds;
}

for my $method (@delegate_to_insert_storage) {
  no strict 'refs';

  *{$method} = Sub::Name::subname $method => sub {
    my $self = shift;
    $self->_insert_storage->$method(@_) if $self->_insert_storage;
    return $self->next::method(@_);
  };
}

# Make sure we have CHAINED mode turned on if AutoCommit is off in non-FreeTDS
# DBD::Sybase (since we don't know how DBD::Sybase was compiled.) If however
# we're using FreeTDS, CHAINED mode turns on an implicit transaction which we
# only want when AutoCommit is off.
sub _populate_dbh {
  my $self = shift;

  $self->next::method(@_);

  if (not $self->using_freetds) {
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

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  my ($sql, $bind) = $self->next::method (@_);

  if ($op eq 'insert') {
    my $table = $ident->from;

    my $bind_info = $self->_resolve_column_info(
      $ident, [map $_->[0], @{$bind}]
    );
    my $identity_col = List::Util::first
      { $bind_info->{$_}{is_auto_increment} }
      (keys %$bind_info)
    ;

    if ($identity_col) {
      $sql = join ("\n",
        "SET IDENTITY_INSERT $table ON",
        $sql,
        "SET IDENTITY_INSERT $table OFF",
      );
    }
    else {
      $identity_col = List::Util::first
        { $ident->column_info($_)->{is_auto_increment} }
        $ident->columns
      ;
    }

    if ($identity_col) {
      $sql =
        "$sql\n" .
        $self->_fetch_identity_sql($ident, $identity_col);
    }
  }

  return ($sql, $bind);
}

# Stolen from SQLT, with some modifications. This is a makeshift
# solution before a sane type-mapping library is available, thus
# the 'our' for easy overrides.
our %TYPE_MAPPING  = (
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

sub _native_data_type {
  my ($self, $type) = @_;

  $type = lc $type;
  $type =~ s/\s* identity//x;

  return uc($TYPE_MAPPING{$type} || $type);
}

sub _fetch_identity_sql {
  my ($self, $source, $col) = @_;

  return sprintf ("SELECT MAX(%s) FROM %s",
    map { $self->sql_maker->_quote ($_) } ($col, $source->from)
  );
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

# handles TEXT/IMAGE and transaction for last_insert_id
sub insert {
  my $self = shift;
  my ($source, $to_insert) = @_;

  my $blob_cols = $self->_remove_blob_cols($source, $to_insert);

  my $identity_col = List::Util::first
    { $source->column_info($_)->{is_auto_increment} }
    $source->columns;

  # do we need the horrific SELECT MAX(COL) hack?
  my $dumb_last_insert_id =
       $identity_col
    && (not exists $to_insert->{$identity_col})
    && ($self->_identity_method||'') ne '@@IDENTITY';

  my $next = $self->next::can;

  # we are already in a transaction, or there are no blobs
  # and we don't need the PK - just (try to) do it
  if ($self->{transaction_depth}
        || (!$blob_cols && !$dumb_last_insert_id) 
  ) {
    return $self->_insert (
      $next, $source, $to_insert, $blob_cols, $identity_col
    );
  }

  # otherwise use the _insert_storage to do the insert+transaction on another
  # connection
  my $guard = $self->_insert_storage->txn_scope_guard;

  my $updated_cols = $self->_insert_storage->_insert (
    $next, $source, $to_insert, $blob_cols, $identity_col
  );

  $self->_identity($self->_insert_storage->_identity);

  $guard->commit;

  return $updated_cols;
}

sub _insert {
  my ($self, $next, $source, $to_insert, $blob_cols, $identity_col) = @_;

  my $updated_cols = $self->$next ($source, $to_insert);

  my $final_row = {
    $identity_col => $self->last_insert_id($source, $identity_col),
    %$to_insert,
    %$updated_cols,
  };

  $self->_insert_blobs ($source, $blob_cols, $final_row) if $blob_cols;

  return $updated_cols;
}

sub update {
  my $self = shift;
  my ($source, $fields, $where) = @_;

  my $wantarray = wantarray;
  my $blob_cols = $self->_remove_blob_cols($source, $fields);

  if (not $blob_cols) {
    return $self->next::method(@_);
  }

# update+blob update(s) done atomically on separate connection
  $self = $self->_insert_storage;

  my $guard = $self->txn_scope_guard;

  my @res;
  if ($wantarray) {
    @res    = $self->next::method(@_);
  }
  elsif (defined $wantarray) {
    $res[0] = $self->next::method(@_);
  }
  else {
    $self->next::method(@_);
  }

  $self->_update_blobs($source, $blob_cols, $where);

  $guard->commit;

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

  return keys %blob_cols ? \%blob_cols : undef;
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
    my $cursor = $self->select ($source, \@primary_cols, $where, {});
    @rows = map {
      my %row; @row{@primary_cols} = @$_; \%row
    } $cursor->all;
  }

  for my $row (@rows) {
    $self->_insert_blobs($source, $blob_cols, $row);
  }
}

sub _insert_blobs {
  my ($self, $source, $blob_cols, $row) = @_;
  my $dbh = $self->_get_dbh;

  my $table = $source->from;

  my %row = %$row;
  my (@primary_cols) = $source->primary_columns;

  croak "Cannot update TEXT/IMAGE column(s) without a primary key"
    unless @primary_cols;

  if ((grep { defined $row{$_} } @primary_cols) != @primary_cols) {
    croak "Cannot update TEXT/IMAGE column(s) without primary key values";
  }

  for my $col (keys %$blob_cols) {
    my $blob = $blob_cols->{$col};

    my %where = map { ($_, $row{$_}) } @primary_cols;

    my $cursor = $self->select ($source, [$col], \%where, {});
    $cursor->next;
    my $sth = $cursor->sth;

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
      if ($self->using_freetds) {
        croak (
          'TEXT/IMAGE operation failed, probably because you are using FreeTDS: '
          . $exception
        );
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
      # amazingly, this works with FreeTDS
      $dbh->syb_date_fmt('ISO_strict');
    } elsif (not $old_dbd_warned) {
      carp "Your DBD::Sybase is too old to support ".
      "DBIx::Class::InflateColumn::DateTime, please upgrade!";
      $old_dbd_warned = 1;
    }

    $dbh->do('SET DATEFORMAT mdy');

    1;
  }
}

sub datetime_parser_type { "DateTime::Format::Sybase" }

# ->begin_work and such have no effect with FreeTDS but we run them anyway to
# let the DBD keep any state it needs to.
#
# If they ever do start working, the extra statements will do no harm (because
# Sybase supports nested transactions.)

sub _dbh_begin_work {
  my $self = shift;
  $self->next::method(@_);
  if ($self->using_freetds) {
    $self->_get_dbh->do('BEGIN TRAN');
  }
}

sub _dbh_commit {
  my $self = shift;
  if ($self->using_freetds) {
    $self->_dbh->do('COMMIT');
  }
  return $self->next::method(@_);
}

sub _dbh_rollback {
  my $self = shift;
  if ($self->using_freetds) {
    $self->_dbh->do('ROLLBACK');
  }
  return $self->next::method(@_);
}

# savepoint support using ASE syntax

sub _svp_begin {
  my ($self, $name) = @_;

  $self->_get_dbh->do("SAVE TRANSACTION $name");
}

# A new SAVE TRANSACTION with the same name releases the previous one.
sub _svp_release { 1 }

sub _svp_rollback {
  my ($self, $name) = @_;

  $self->_get_dbh->do("ROLLBACK TRANSACTION $name");
}

1;

=head1 Schema::Loader Support

There is an experimental branch of L<DBIx::Class::Schema::Loader> that will
allow you to dump a schema from most (if not all) versions of Sybase.

It is available via subversion from:

  http://dev.catalyst.perl.org/repos/bast/branches/DBIx-Class-Schema-Loader/current/

=head1 FreeTDS

This driver supports L<DBD::Sybase> compiled against FreeTDS
(L<http://www.freetds.org/>) to the best of our ability, however it is
recommended that you recompile L<DBD::Sybase> against the Sybase Open Client
libraries. They are a part of the Sybase ASE distribution:

The Open Client FAQ is here:
L<http://www.isug.com/Sybase_FAQ/ASE/section7.html>.

Sybase ASE for Linux (which comes with the Open Client libraries) may be
downloaded here: L<http://response.sybase.com/forms/ASE_Linux_Download>.

To see if you're using FreeTDS check C<< $schema->storage->using_freetds >>, or run:

  perl -MDBI -le 'my $dbh = DBI->connect($dsn, $user, $pass); print $dbh->{syb_oc_version}'

Some versions of the libraries involved will not support placeholders, in which
case the storage will be reblessed to
L<DBIx::Class::Storage::DBI::Sybase::NoBindVars>.

In some configurations, placeholders will work but will throw implicit type
conversion errors for anything that's not expecting a string. In such a case,
the C<auto_cast> option from L<DBIx::Class::Storage::DBI::AutoCast> is
automatically set, which you may enable on connection with
L<DBIx::Class::Storage::DBI::AutoCast/connect_call_set_auto_cast>. The type info
for the C<CAST>s is taken from the L<DBIx::Class::ResultSource/data_type>
definitions in your Result classes, and are mapped to a Sybase type (if it isn't
already) using a mapping based on L<SQL::Translator>.

In other configurations, placeholers will work just as they do with the Sybase
Open Client libraries.

Inserts or updates of TEXT/IMAGE columns will B<NOT> work with FreeTDS.

=head1 INSERTS WITH PLACEHOLDERS

With placeholders enabled, inserts are done in a transaction so that there are
no concurrency issues with getting the inserted identity value using
C<SELECT MAX(col)>, which is the only way to get the C<IDENTITY> value in this
mode.

In addition, they are done on a separate connection so that it's possible to
have active cursors when doing an insert.

When using C<DBIx::Class::Storage::DBI::Sybase::NoBindVars> transactions are
disabled, as there are no concurrency issues with C<SELECT @@IDENTITY> as it's a
session variable.

=head1 TRANSACTIONS

Due to limitations of the TDS protocol, L<DBD::Sybase>, or both; you cannot
begin a transaction while there are active cursors. An active cursor is, for
example, a L<ResultSet|DBIx::Class::ResultSet> that has been executed using
C<next> or C<first> but has not been exhausted or
L<reset|DBIx::Class::ResultSet/reset>.

For example, this will not work:

  $schema->txn_do(sub {
    my $rs = $schema->resultset('Book');
    while (my $row = $rs->next) {
      $schema->resultset('MetaData')->create({
        book_id => $row->id,
        ...
      });
    }
  });

Transactions done for inserts in C<AutoCommit> mode when placeholders are in use
are not affected, as they are done on an extra database handle.

Some workarounds:

=over 4

=item * use L<DBIx::Class::Storage::DBI::Replicated>

=item * L<connect|DBIx::Class::Schema/connect> another L<Schema|DBIx::Class::Schema>

=item * load the data from your cursor with L<DBIx::Class::ResultSet/all>

=back

=head1 MAXIMUM CONNECTIONS

The TDS protocol makes separate connections to the server for active statements
in the background. By default the number of such connections is limited to 25,
on both the client side and the server side.

This is a bit too low for a complex L<DBIx::Class> application, so on connection
the client side setting is set to C<256> (see L<DBD::Sybase/maxConnect>.) You
can override it to whatever setting you like in the DSN.

See
L<http://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.help.ase_15.0.sag1/html/sag1/sag1272.htm>
for information on changing the setting on the server side.

=head1 DATES

See L</connect_call_datetime_setup> to setup date formats
for L<DBIx::Class::InflateColumn::DateTime>.

=head1 TEXT/IMAGE COLUMNS

L<DBD::Sybase> compiled with FreeTDS will B<NOT> allow you to insert or update
C<TEXT/IMAGE> columns.

Setting C<< $dbh->{LongReadLen} >> will also not work with FreeTDS use either:

  $schema->storage->dbh->do("SET TEXTSIZE $bytes");

or

  $schema->storage->set_textsize($bytes);

instead.

However, the C<LongReadLen> you pass in
L<DBIx::Class::Storage::DBI/connect_info> is used to execute the equivalent
C<SET TEXTSIZE> command on connection.

See L</connect_call_blob_setup> for a L<DBIx::Class::Storage::DBI/connect_info>
setting you need to work with C<IMAGE> columns.

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

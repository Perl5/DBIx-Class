package DBIx::Class::Storage::DBI::MSSQL;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::UniqueIdentifier/;
use mro 'c3';
use Try::Tiny;
use List::Util 'first';
use namespace::clean;

__PACKAGE__->mk_group_accessors(simple => qw/
  _identity _identity_method _pre_insert_sql _post_insert_sql
/);

__PACKAGE__->sql_maker_class('DBIx::Class::SQLMaker::MSSQL');

__PACKAGE__->sql_quote_char([qw/[ ]/]);

__PACKAGE__->datetime_parser_type (
  'DBIx::Class::Storage::DBI::MSSQL::DateTime::Format'
);


__PACKAGE__->new_guid('NEWID()');

sub _set_identity_insert {
  my ($self, $table) = @_;

  my $stmt = 'SET IDENTITY_INSERT %s %s';
  $table   = $self->sql_maker->_quote($table);

  $self->_pre_insert_sql (sprintf $stmt, $table, 'ON');
  $self->_post_insert_sql(sprintf $stmt, $table, 'OFF');
}

sub insert_bulk {
  my $self = shift;
  my ($source, $cols, $data) = @_;

  my $is_identity_insert =
    (first { $_->{is_auto_increment} } values %{ $source->columns_info($cols) } )
      ? 1
      : 0
  ;

  if ($is_identity_insert) {
     $self->_set_identity_insert ($source->name);
  }

  $self->next::method(@_);
}

sub insert {
  my $self = shift;
  my ($source, $to_insert) = @_;

  my $supplied_col_info = $self->_resolve_column_info($source, [keys %$to_insert] );

  my $is_identity_insert =
    (first { $_->{is_auto_increment} } values %$supplied_col_info) ? 1 : 0;

  if ($is_identity_insert) {
     $self->_set_identity_insert ($source->name);
  }

  my $updated_cols = $self->next::method(@_);

  return $updated_cols;
}

sub _prep_for_execute {
  my $self = shift;
  my ($op, $ident, $args) = @_;

# cast MONEY values properly
  if ($op eq 'insert' || $op eq 'update') {
    my $fields = $args->[0];

    my $colinfo = $ident->columns_info([keys %$fields]);

    for my $col (keys %$fields) {
      # $ident is a result source object with INSERT/UPDATE ops
      if (
        $colinfo->{$col}{data_type}
          &&
        $colinfo->{$col}{data_type} =~ /^money\z/i
      ) {
        my $val = $fields->{$col};
        $fields->{$col} = \['CAST(? AS MONEY)', [ $col => $val ]];
      }
    }
  }

  my ($sql, $bind) = $self->next::method (@_);

  if ($op eq 'insert') {
    if (my $prepend = $self->_pre_insert_sql) {
      $sql = "${prepend}\n${sql}";
      $self->_pre_insert_sql(undef);
    }
    if (my $append  = $self->_post_insert_sql) {
      $sql = "${sql}\n${append}";
      $self->_post_insert_sql(undef);
    }
    $sql .= "\nSELECT SCOPE_IDENTITY()";
  }

  return ($sql, $bind);
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->next::method(@_);

  if ($op eq 'insert') {

    # this should bring back the result of SELECT SCOPE_IDENTITY() we tacked
    # on in _prep_for_execute above
    my ($identity) = try { $sth->fetchrow_array };

    # SCOPE_IDENTITY failed, but we can do something else
    if ( (! $identity) && $self->_identity_method) {
      ($identity) = $self->_dbh->selectrow_array(
        'select ' . $self->_identity_method
      );
    }

    $self->_identity($identity);
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id { shift->_identity }

#
# MSSQL is retarded wrt ordered subselects. One needs to add a TOP
# to *all* subqueries, but one also *can't* use TOP 100 PERCENT
# http://sqladvice.com/forums/permalink/18496/22931/ShowThread.aspx#22931
#
sub _select_args_to_query {
  my $self = shift;

  my ($sql, $prep_bind, @rest) = $self->next::method (@_);

  # see if this is an ordered subquery
  my $attrs = $_[3];
  if (
    $sql !~ /^ \s* SELECT \s+ TOP \s+ \d+ \s+ /xi
      &&
    scalar $self->_extract_order_criteria ($attrs->{order_by})
  ) {
    $self->throw_exception(
      'An ordered subselect encountered - this is not safe! Please see "Ordered Subselects" in DBIx::Class::Storage::DBI::MSSQL
    ') unless $attrs->{unsafe_subselect_ok};
    my $max = $self->sql_maker->__max_int;
    $sql =~ s/^ \s* SELECT \s/SELECT TOP $max /xi;
  }

  return wantarray
    ? ($sql, $prep_bind, @rest)
    : \[ "($sql)", @$prep_bind ]
  ;
}


# savepoint syntax is the same as in Sybase ASE

sub _exec_svp_begin {
  my ($self, $name) = @_;

  $self->_dbh->do("SAVE TRANSACTION $name");
}

# A new SAVE TRANSACTION with the same name releases the previous one.
sub _exec_svp_release { 1 }

sub _exec_svp_rollback {
  my ($self, $name) = @_;

  $self->_dbh->do("ROLLBACK TRANSACTION $name");
}

sub sqlt_type { 'SQLServer' }

sub sql_limit_dialect {
  my $self = shift;

  my $supports_rno = 0;

  if (exists $self->_server_info->{normalized_dbms_version}) {
    $supports_rno = 1 if $self->_server_info->{normalized_dbms_version} >= 9;
  }
  else {
    # User is connecting via DBD::Sybase and has no permission to run
    # stored procedures like xp_msver, or version detection failed for some
    # other reason.
    # So, we use a query to check if RNO is implemented.
    try {
      $self->_get_dbh->selectrow_array('SELECT row_number() OVER (ORDER BY rand())');
      $supports_rno = 1;
    };
  }

  return $supports_rno ? 'RowNumberOver' : 'Top';
}

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  local $dbh->{RaiseError} = 1;
  local $dbh->{PrintError} = 0;

  return try {
    $dbh->do('select 1');
    1;
  } catch {
    0;
  };
}

package # hide from PAUSE
  DBIx::Class::Storage::DBI::MSSQL::DateTime::Format;

my $datetime_format      = '%Y-%m-%d %H:%M:%S.%3N'; # %F %T
my $smalldatetime_format = '%Y-%m-%d %H:%M:%S';

my ($datetime_parser, $smalldatetime_parser);

sub parse_datetime {
  shift;
  require DateTime::Format::Strptime;
  $datetime_parser ||= DateTime::Format::Strptime->new(
    pattern  => $datetime_format,
    on_error => 'croak',
  );
  return $datetime_parser->parse_datetime(shift);
}

sub format_datetime {
  shift;
  require DateTime::Format::Strptime;
  $datetime_parser ||= DateTime::Format::Strptime->new(
    pattern  => $datetime_format,
    on_error => 'croak',
  );
  return $datetime_parser->format_datetime(shift);
}

sub parse_smalldatetime {
  shift;
  require DateTime::Format::Strptime;
  $smalldatetime_parser ||= DateTime::Format::Strptime->new(
    pattern  => $smalldatetime_format,
    on_error => 'croak',
  );
  return $smalldatetime_parser->parse_datetime(shift);
}

sub format_smalldatetime {
  shift;
  require DateTime::Format::Strptime;
  $smalldatetime_parser ||= DateTime::Format::Strptime->new(
    pattern  => $smalldatetime_format,
    on_error => 'croak',
  );
  return $smalldatetime_parser->format_datetime(shift);
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::MSSQL - Base Class for Microsoft SQL Server support
in DBIx::Class

=head1 SYNOPSIS

This is the base class for Microsoft SQL Server support, used by
L<DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server> and
L<DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server>.

=head1 IMPLEMENTATION NOTES

=head2 IDENTITY information

Microsoft SQL Server supports three methods of retrieving the IDENTITY
value for inserted row: IDENT_CURRENT, @@IDENTITY, and SCOPE_IDENTITY().
SCOPE_IDENTITY is used here because it is the safest.  However, it must
be called is the same execute statement, not just the same connection.

So, this implementation appends a SELECT SCOPE_IDENTITY() statement
onto each INSERT to accommodate that requirement.

C<SELECT @@IDENTITY> can also be used by issuing:

  $self->_identity_method('@@identity');

it will only be used if SCOPE_IDENTITY() fails.

This is more dangerous, as inserting into a table with an on insert trigger that
inserts into another table with an identity will give erroneous results on
recent versions of SQL Server.

=head2 identity insert

Be aware that we have tried to make things as simple as possible for our users.
For MSSQL that means that when a user tries to create a row, while supplying an
explicit value for an autoincrementing column, we will try to issue the
appropriate database call to make this possible, namely C<SET IDENTITY_INSERT
$table_name ON>. Unfortunately this operation in MSSQL requires the
C<db_ddladmin> privilege, which is normally not included in the standard
write-permissions.

=head2 Ordered Subselects

If you attempted the following query (among many others) in Microsoft SQL
Server

 $rs->search ({}, {
  prefetch => 'relation',
  rows => 2,
  offset => 3,
 });

You may be surprised to receive an exception. The reason for this is a quirk
in the MSSQL engine itself, and sadly doesn't have a sensible workaround due
to the way DBIC is built. DBIC can do truly wonderful things with the aid of
subselects, and does so automatically when necessary. The list of situations
when a subselect is necessary is long and still changes often, so it can not
be exhaustively enumerated here. The general rule of thumb is a joined
L<has_many|DBIx::Class::Relationship/has_many> relationship with limit/group
applied to the left part of the join.

In its "pursuit of standards" Microsft SQL Server goes to great lengths to
forbid the use of ordered subselects. This breaks a very useful group of
searches like "Give me things number 4 to 6 (ordered by name), and prefetch
all their relations, no matter how many". While there is a hack which fools
the syntax checker, the optimizer may B<still elect to break the subselect>.
Testing has determined that while such breakage does occur (the test suite
contains an explicit test which demonstrates the problem), it is relative
rare. The benefits of ordered subselects are on the other hand too great to be
outright disabled for MSSQL.

Thus compromise between usability and perfection is the MSSQL-specific
L<resultset attribute|DBIx::Class::ResultSet/ATTRIBUTES> C<unsafe_subselect_ok>.
It is deliberately not possible to set this on the Storage level, as the user
should inspect (and preferably regression-test) the return of every such
ResultSet individually. The example above would work if written like:

 $rs->search ({}, {
  unsafe_subselect_ok => 1,
  prefetch => 'relation',
  rows => 2,
  offset => 3,
 });

If it is possible to rewrite the search() in a way that will avoid the need
for this flag - you are urged to do so. If DBIC internals insist that an
ordered subselect is necessary for an operation, and you believe there is a
different/better way to get the same result - please file a bugreport.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

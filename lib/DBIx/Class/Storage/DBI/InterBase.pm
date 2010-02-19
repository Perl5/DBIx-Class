package DBIx::Class::Storage::DBI::InterBase;

# partly stolen from DBIx::Class::Storage::DBI::MSSQL

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';
use List::Util();

__PACKAGE__->mk_group_accessors(simple => qw/
  _auto_incs
/);

=head1 NAME

DBIx::Class::Storage::DBI::InterBase - Driver for the Firebird RDBMS

=head1 DESCRIPTION

This class implements autoincrements for Firebird using C<RETURNING>, sets the
limit dialect to C<FIRST X SKIP X> and provides preliminary
L<DBIx::Class::InflateColumn::DateTime> support.

For ODBC support, see L<DBIx::Class::Storage::DBI::ODBC::Firebird>.

To turn on L<DBIx::Class::InflateColumn::DateTime> support, see
L</connect_call_datetime_setup>.

=cut

sub _prep_for_execute {
  my $self = shift;
  my ($op, $extra_bind, $ident, $args) = @_;

  if ($op eq 'insert') {
    my @pk = $ident->_pri_cols;
    my %pk;
    @pk{@pk} = ();

    my @auto_inc_cols = grep {
      my $inserting = $args->[0]{$_};

      ($ident->column_info($_)->{is_auto_increment}
        || exists $pk{$_})
      && (
        (not defined $inserting)
        ||
        (ref $inserting eq 'SCALAR' && $$inserting =~ /^null\z/i)
      )
    } $ident->columns;

    if (@auto_inc_cols) {
      $args->[1]{returning} = \@auto_inc_cols;

      $self->_auto_incs([]);
      $self->_auto_incs->[0] = \@auto_inc_cols;
    }
  }

  return $self->next::method(@_);
}

sub _execute {
  my $self = shift;
  my ($op) = @_;

  my ($rv, $sth, @bind) = $self->dbh_do($self->can('_dbh_execute'), @_);

  if ($op eq 'insert' && $self->_auto_incs) {
    local $@;
    my (@auto_incs) = eval {
      local $SIG{__WARN__} = sub {};
      $sth->fetchrow_array
    };
    $self->_auto_incs->[1] = \@auto_incs;
    $sth->finish;
  }

  return wantarray ? ($rv, $sth, @bind) : $rv;
}

sub last_insert_id {
  my ($self, $source, @cols) = @_;
  my @result;

  my %auto_incs;
  @auto_incs{ @{ $self->_auto_incs->[0] } } =
    @{ $self->_auto_incs->[1] };

  push @result, $auto_incs{$_} for @cols;

  return @result;
}

# this sub stolen from DB2

sub _sql_maker_opts {
  my ( $self, $opts ) = @_;

  if ( $opts ) {
    $self->{_sql_maker_opts} = { %$opts };
  }

  return { limit_dialect => 'FirstSkip', %{$self->{_sql_maker_opts}||{}} };
}

sub _svp_begin {
    my ($self, $name) = @_;

    $self->_get_dbh->do("SAVEPOINT $name");
}

sub _svp_release {
    my ($self, $name) = @_;

    $self->_get_dbh->do("RELEASE SAVEPOINT $name");
}

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->_get_dbh->do("ROLLBACK TO SAVEPOINT $name")
}

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  local $dbh->{RaiseError} = 1;

  eval {
    $dbh->do('select 1 from rdb$database');
  };

  return $@ ? 0 : 1;
}

# We want dialect 3 for new features and quoting to work, DBD::InterBase uses
# dialect 1 (interbase compat) by default.
sub _init {
  my $self = shift;
  $self->_set_sql_dialect(3);
}

sub _set_sql_dialect {
  my $self = shift;
  my $val  = shift || 3;

  my $dsn = $self->_dbi_connect_info->[0];

  return if ref($dsn) eq 'CODE';

  if ($dsn !~ /ib_dialect=/) {
    $self->_dbi_connect_info->[0] = "$dsn;ib_dialect=$val";
    my $connected = defined $self->_dbh;
    $self->disconnect;
    $self->ensure_connected if $connected;
  }
}

# softcommit makes savepoints work
sub _run_connection_actions {
  my $self = shift;

  $self->_dbh->{ib_softcommit} = 1;

  $self->next::method(@_);
}

=head2 connect_call_datetime_setup

Used as:

  on_connect_call => 'datetime_setup'

In L<connect_info|DBIx::Class::Storage::DBI/connect_info> to set the date and
timestamp formats using:

  $dbh->{ib_time_all} = 'ISO';

See L<DBD::InterBase> for more details.

The C<TIMESTAMP> data type supports up to 4 digits after the decimal point for
second precision. The full precision is used.

The C<DATE> data type stores the date portion only, and it B<MUST> be declared
with:

  data_type => 'date'

in your Result class.

Timestamp columns can be declared with either C<datetime> or C<timestamp>.

You will need the L<DateTime::Format::Strptime> module for inflation to work.

For L<DBIx::Class::Storage::DBI::ODBC::Firebird>, this is a noop and sub-second
precision is not currently available.

=cut

sub connect_call_datetime_setup {
  my $self = shift;

  $self->_get_dbh->{ib_time_all} = 'ISO';
}

sub datetime_parser_type {
  'DBIx::Class::Storage::DBI::InterBase::DateTime::Format'
}

package # hide from PAUSE
  DBIx::Class::Storage::DBI::InterBase::DateTime::Format;

my $timestamp_format = '%Y-%m-%d %H:%M:%S.%4N'; # %F %T
my $date_format      = '%Y-%m-%d';

my ($timestamp_parser, $date_parser);

sub parse_datetime {
  shift;
  require DateTime::Format::Strptime;
  $timestamp_parser ||= DateTime::Format::Strptime->new(
    pattern  => $timestamp_format,
    on_error => 'croak',
  );
  return $timestamp_parser->parse_datetime(shift);
}

sub format_datetime {
  shift;
  require DateTime::Format::Strptime;
  $timestamp_parser ||= DateTime::Format::Strptime->new(
    pattern  => $timestamp_format,
    on_error => 'croak',
  );
  return $timestamp_parser->format_datetime(shift);
}

sub parse_date {
  shift;
  require DateTime::Format::Strptime;
  $date_parser ||= DateTime::Format::Strptime->new(
    pattern  => $date_format,
    on_error => 'croak',
  );
  return $date_parser->parse_datetime(shift);
}

sub format_date {
  shift;
  require DateTime::Format::Strptime;
  $date_parser ||= DateTime::Format::Strptime->new(
    pattern  => $date_format,
    on_error => 'croak',
  );
  return $date_parser->format_datetime(shift);
}

1;

=head1 CAVEATS

=over 4

=item *

C<last_insert_id> support only works for Firebird versions 2 or greater. To
work with earlier versions, we'll need to figure out how to retrieve the bodies
of C<BEFORE INSERT> triggers and parse them for the C<GENERATOR> name.

=back

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

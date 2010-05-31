package DBIx::Class::Storage::DBI::mysql;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

__PACKAGE__->sql_maker_class('DBIx::Class::SQLMaker::MySQL');
__PACKAGE__->sql_limit_dialect ('LimitXY');
__PACKAGE__->sql_quote_char ('`');

__PACKAGE__->_use_multicolumn_in (1);

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  $self->_do_query('SET FOREIGN_KEY_CHECKS = 0');
  $sub->();
  $self->_do_query('SET FOREIGN_KEY_CHECKS = 1');
}

sub connect_call_set_strict_mode {
  my $self = shift;

  # the @@sql_mode puts back what was previously set on the session handle
  $self->_do_query(q|SET SQL_MODE = CONCAT('ANSI,TRADITIONAL,ONLY_FULL_GROUP_BY,', @@sql_mode)|);
  $self->_do_query(q|SET SQL_AUTO_IS_NULL = 0|);
}

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;
  $dbh->{mysql_insertid};
}

# here may seem like an odd place to override, but this is the first
# method called after we are connected *and* the driver is determined
# ($self is reblessed). See code flow in ::Storage::DBI::_populate_dbh
sub _run_connection_actions {
  my $self = shift;

  # default mysql_auto_reconnect to off unless explicitly set
  if (
    $self->_dbh->{mysql_auto_reconnect}
      and
    ! exists $self->_dbic_connect_attributes->{mysql_auto_reconnect}
  ) {
    $self->_dbh->{mysql_auto_reconnect} = 0;
  }

  $self->next::method(@_);
}

# we need to figure out what mysql version we're running
sub sql_maker {
  my $self = shift;

  unless ($self->_sql_maker) {
    my $maker = $self->next::method (@_);

    # mysql 3 does not understand a bare JOIN
    my $mysql_ver = $self->_dbh_get_info(18);
    $maker->{_default_jointype} = 'INNER' if $mysql_ver =~ /^3/;
  }

  return $self->_sql_maker;
}

sub sqlt_type {
  return 'MySQL';
}

sub deployment_statements {
  my $self = shift;
  my ($schema, $type, $version, $dir, $sqltargs, @rest) = @_;

  $sqltargs ||= {};

  if (
    ! exists $sqltargs->{producer_args}{mysql_version}
      and
    my $dver = $self->_server_info->{normalized_dbms_version}
  ) {
    $sqltargs->{producer_args}{mysql_version} = $dver;
  }

  $self->next::method($schema, $type, $version, $dir, $sqltargs, @rest);
}

sub _exec_svp_begin {
    my ($self, $name) = @_;

    $self->_dbh->do("SAVEPOINT $name");
}

sub _exec_svp_release {
    my ($self, $name) = @_;

    $self->_dbh->do("RELEASE SAVEPOINT $name");
}

sub _exec_svp_rollback {
    my ($self, $name) = @_;

    $self->_dbh->do("ROLLBACK TO SAVEPOINT $name")
}

sub is_replicating {
    my $status = shift->_get_dbh->selectrow_hashref('show slave status');
    return ($status->{Slave_IO_Running} eq 'Yes') && ($status->{Slave_SQL_Running} eq 'Yes');
}

sub lag_behind_master {
    return shift->_get_dbh->selectrow_hashref('show slave status')->{Seconds_Behind_Master};
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::mysql - Storage::DBI class implementing MySQL specifics

=head1 SYNOPSIS

Storage::DBI autodetects the underlying MySQL database, and re-blesses the
C<$storage> object into this class.

  my $schema = MyDb::Schema->connect( $dsn, $user, $pass, { on_connect_call => 'set_strict_mode' } );

=head1 DESCRIPTION

This class implements MySQL specific bits of L<DBIx::Class::Storage::DBI>,
like AutoIncrement column support and savepoints. Also it augments the
SQL maker to support the MySQL-specific C<STRAIGHT_JOIN> join type, which
you can use by specifying C<< join_type => 'straight' >> in the
L<relationship attributes|DBIx::Class::Relationship::Base/join_type>


It also provides a one-stop on-connect macro C<set_strict_mode> which sets
session variables such that MySQL behaves more predictably as far as the
SQL standard is concerned.

=head1 STORAGE OPTIONS

=head2 set_strict_mode

Enables session-wide strict options upon connecting. Equivalent to:

  ->connect ( ... , {
    on_connect_do => [
      q|SET SQL_MODE = CONCAT('ANSI,TRADITIONAL,ONLY_FULL_GROUP_BY,', @@sql_mode)|,
      q|SET SQL_AUTO_IS_NULL = 0|,
    ]
  });

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

package DBIx::Class::Storage::DBI::Informix;
use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';
use mro 'c3';

use Try::Tiny;
use namespace::clean;

__PACKAGE__->sql_limit_dialect ('SkipFirst');
__PACKAGE__->sql_quote_char ('"');
__PACKAGE__->datetime_parser_type (
  'DBIx::Class::Storage::DBI::Informix::DateTime::Format'
);


__PACKAGE__->mk_group_accessors('simple' => '__last_insert_id');

=head1 NAME

DBIx::Class::Storage::DBI::Informix - Base Storage Class for Informix Support

=head1 DESCRIPTION

This class implements storage-specific support for the Informix RDBMS

=head1 METHODS

=cut

__PACKAGE__->_unsatisfied_deferred_constraints_autorollback(1);

sub _set_constraints_deferred {
  $_[0]->_do_query('SET CONSTRAINTS ALL DEFERRED');
}

# Constraints are deferred only for the current transaction, new transactions
# start with constraints IMMEDIATE by default. If we are already in a
# transaction when with_deferred_fk_checks is fired, we want to switch
# constraints back to IMMEDIATE mode at the end of the savepoint or "nested
# transaction" so that they can be checked.

sub _set_constraints_immediate {
  $_[0]->_do_query('SET CONSTRAINTS ALL IMMEDIATE') if $_[0]->transaction_depth;
}

# A failed commit due to unsatisfied deferred FKs throws a "DBD driver has not
# implemented the AutoCommit attribute" exception, masking the actual error. We
# fix it up here by doing a manual $dbh->do("COMMIT WORK"), propagating the
# exception, and resetting the $dbh->{AutoCommit} attribute.

sub _exec_txn_commit {
  my $self = shift;

  my $tried_resetting_autocommit = 0;

  try {
    $self->_dbh->do('COMMIT WORK');
    if ($self->_dbh_autocommit && $self->transaction_depth == 1) {
      eval {
        $tried_resetting_autocommit = 1;
        $self->_dbh->{AutoCommit} = 1;
      };
      if ($@) {
        $self->throw_exception('$dbh->{AutoCommit} = 1 failed: '.$@);
      }
    }
  }
  catch {
    my $e = $_;
    if ((not $tried_resetting_autocommit) &&
        $self->_dbh_autocommit && $self->transaction_depth == 1) {
      eval {
        $self->_dbh->{AutoCommit} = 1
      };
      if ($@ && $@ !~ /DBD driver has not implemented the AutoCommit attribute/) {
        $e .= ' also $dbh->{AutoCommit} = 1 failed: '.$@;
      }
    }
    $self->throw_exception($e);
  };
}

sub _execute {
  my $self = shift;
  my ($op) = @_;
  my ($rv, $sth, @rest) = $self->next::method(@_);

  $self->__last_insert_id($sth->{ix_sqlerrd}[1])
    if $self->_perform_autoinc_retrieval;

  return (wantarray ? ($rv, $sth, @rest) : $rv);
}

sub last_insert_id {
  shift->__last_insert_id;
}

sub _exec_svp_begin {
    my ($self, $name) = @_;

    $self->_dbh->do("SAVEPOINT $name");
}

# can't release savepoints
sub _exec_svp_release { 1 }

sub _exec_svp_rollback {
    my ($self, $name) = @_;

    $self->_dbh->do("ROLLBACK TO SAVEPOINT $name")
}

=head2 connect_call_datetime_setup

Used as:

  on_connect_call => 'datetime_setup'

In L<connect_info|DBIx::Class::Storage::DBI/connect_info> to set the C<DATE> and
C<DATETIME> formats.

Sets the following environment variables:

    GL_DATE="%m/%d/%Y"
    GL_DATETIME="%Y-%m-%d %H:%M:%S%F5"

The C<DBDATE> and C<DBCENTURY> environment variables are cleared.

B<NOTE:> setting the C<GL_DATE> environment variable seems to have no effect
after the process has started, so the default format is used. The C<GL_DATETIME>
setting does take effect however.

The C<DATETIME> data type supports up to 5 digits after the decimal point for
second precision, depending on how you have declared your column. The full
possible precision is used.

The column declaration for a C<DATETIME> with maximum precision is:

  column_name DATETIME YEAR TO FRACTION(5)

The C<DATE> data type stores the date portion only, and it B<MUST> be declared
with:

  data_type => 'date'

in your Result class.

You will need the L<DateTime::Format::Strptime> module for inflation to work.

=cut

sub connect_call_datetime_setup {
  my $self = shift;

  delete @ENV{qw/DBDATE DBCENTURY/};

  $ENV{GL_DATE}     = "%m/%d/%Y";
  $ENV{GL_DATETIME} = "%Y-%m-%d %H:%M:%S%F5";
}

package # hide from PAUSE
  DBIx::Class::Storage::DBI::Informix::DateTime::Format;

my $timestamp_format = '%Y-%m-%d %H:%M:%S.%5N'; # %F %T
my $date_format      = '%m/%d/%Y';

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

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

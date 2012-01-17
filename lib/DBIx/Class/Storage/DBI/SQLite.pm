package DBIx::Class::Storage::DBI::SQLite;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

use DBIx::Class::Carp;
use Scalar::Util 'looks_like_number';
use namespace::clean;

__PACKAGE__->sql_maker_class('DBIx::Class::SQLMaker::SQLite');
__PACKAGE__->sql_limit_dialect ('LimitOffset');
__PACKAGE__->sql_quote_char ('"');
__PACKAGE__->datetime_parser_type ('DateTime::Format::SQLite');

=head1 NAME

DBIx::Class::Storage::DBI::SQLite - Automatic primary key class for SQLite

=head1 SYNOPSIS

  # In your table classes
  use base 'DBIx::Class::Core';
  __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for SQLite.

=head1 METHODS

=cut

sub backup {

  require File::Spec;
  require File::Copy;
  require POSIX;

  my ($self, $dir) = @_;
  $dir ||= './';

  ## Where is the db file?
  my $dsn = $self->_dbi_connect_info()->[0];

  my $dbname = $1 if($dsn =~ /dbname=([^;]+)/);
  if(!$dbname)
  {
    $dbname = $1 if($dsn =~ /^dbi:SQLite:(.+)$/i);
  }
  $self->throw_exception("Cannot determine name of SQLite db file")
    if(!$dbname || !-f $dbname);

#  print "Found database: $dbname\n";
#  my $dbfile = file($dbname);
  my ($vol, $dbdir, $file) = File::Spec->splitpath($dbname);
#  my $file = $dbfile->basename();
  $file = POSIX::strftime("%Y-%m-%d-%H_%M_%S", localtime()) . $file;
  $file = "B$file" while(-f $file);

  mkdir($dir) unless -f $dir;
  my $backupfile = File::Spec->catfile($dir, $file);

  my $res = File::Copy::copy($dbname, $backupfile);
  $self->throw_exception("Backup failed! ($!)") if(!$res);

  return $backupfile;
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

  # For some reason this statement changes the value of $dbh->{AutoCommit}, so
  # we localize it here to preserve the original value.
  local $self->_dbh->{AutoCommit} = $self->_dbh->{AutoCommit};

  $self->_dbh->do("ROLLBACK TRANSACTION TO SAVEPOINT $name");
}

sub deployment_statements {
  my $self = shift;
  my ($schema, $type, $version, $dir, $sqltargs, @rest) = @_;

  $sqltargs ||= {};

  if (
    ! exists $sqltargs->{producer_args}{sqlite_version}
      and
    my $dver = $self->_server_info->{normalized_dbms_version}
  ) {
    $sqltargs->{producer_args}{sqlite_version} = $dver;
  }

  $self->next::method($schema, $type, $version, $dir, $sqltargs, @rest);
}

sub bind_attribute_by_data_type {
  $_[1] =~ /^ (?: int(?:eger)? | (?:tiny|small|medium)int ) $/ix
    ? do { require DBI; DBI::SQL_INTEGER() }
    : undef
  ;
}

# DBD::SQLite (at least up to version 1.31 has a bug where it will
# non-fatally nummify a string value bound as an integer, resulting
# in insertions of '0' into supposed-to-be-numeric fields
# Since this can result in severe data inconsistency, remove the
# bind attr if such a sitation is detected
#
# FIXME - when a DBD::SQLite version is released that eventually fixes
# this sutiation (somehow) - no-op this override once a proper DBD
# version is detected
sub _dbi_attrs_for_bind {
  my ($self, $ident, $bind) = @_;
  my $bindattrs = $self->next::method($ident, $bind);

  for (0.. $#$bindattrs) {
    if (
      defined $bindattrs->[$_]
        and
      defined $bind->[$_][1]
        and
      $bindattrs->[$_] eq DBI::SQL_INTEGER()
        and
      ! looks_like_number ($bind->[$_][1])
    ) {
      carp_unique( sprintf (
        "Non-numeric value supplied for column '%s' despite the numeric datatype",
        $bind->[$_][0]{dbic_colname} || "# $_"
      ) );
      undef $bindattrs->[$_];
    }
  }

  return $bindattrs;
}

=head2 connect_call_use_foreign_keys

Used as:

    on_connect_call => 'use_foreign_keys'

In L<connect_info|DBIx::Class::Storage::DBI/connect_info> to turn on foreign key
(including cascading) support for recent versions of SQLite and L<DBD::SQLite>.

Executes:

  PRAGMA foreign_keys = ON

See L<http://www.sqlite.org/foreignkeys.html> for more information.

=cut

sub connect_call_use_foreign_keys {
  my $self = shift;

  $self->_do_query(
    'PRAGMA foreign_keys = ON'
  );
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

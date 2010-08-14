package DBIx::Class::Storage::DBI::SQLite;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

use POSIX 'strftime';
use File::Copy;
use File::Spec;

__PACKAGE__->sql_maker_class('DBIx::Class::SQLAHacks::SQLite');
__PACKAGE__->sql_limit_dialect ('LimitOffset');

sub backup
{
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
  $file = strftime("%Y-%m-%d-%H_%M_%S", localtime()) . $file; 
  $file = "B$file" while(-f $file);

  mkdir($dir) unless -f $dir;
  my $backupfile = File::Spec->catfile($dir, $file);

  my $res = copy($dbname, $backupfile);
  $self->throw_exception("Backup failed! ($!)") if(!$res);

  return $backupfile;
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

sub datetime_parser_type { return "DateTime::Format::SQLite"; } 

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

=head1 NAME

DBIx::Class::Storage::DBI::SQLite - Automatic primary key class for SQLite

=head1 SYNOPSIS

  # In your table classes
  use base 'DBIx::Class::Core';
  __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for SQLite.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

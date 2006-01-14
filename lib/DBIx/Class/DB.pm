package DBIx::Class::DB;

use base qw/DBIx::Class/;
use DBIx::Class::Schema;
use DBIx::Class::Storage::DBI;
use DBIx::Class::ClassResolver::PassThrough;
use DBI;

__PACKAGE__->load_components(qw/ResultSetInstance/);

*dbi_commit = \&txn_commit;
*dbi_rollback = \&txn_rollback;

sub storage { shift->schema_instance(@_)->storage; }

sub resultset_instance {
  my $class = shift;
  my $source = $class->result_source;
  if ($source->result_class ne $class) {
    $source = $source->new($source);
    $source->result_class($class);
  }
  return $source->resultset;
}

=head1 NAME 

DBIx::Class::DB - Simple DBIx::Class Database connection by class inheritance

=head1 SYNOPSIS

  package MyDB;

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components('DB');

  __PACKAGE__->connection('dbi:...', 'user', 'pass', \%attrs);

  package MyDB::MyTable;

  use base qw/MyDB/;
  __PACKAGE__->load_components('Core'); # just load this in MyDB if it will always be there

  ...

=head1 DESCRIPTION

This class provides a simple way of specifying a database connection.

=head1 METHODS

=head2 storage

Sets or gets the storage backend. Defaults to L<DBIx::Class::Storage::DBI>.

=head2 class_resolver ****DEPRECATED****

Sets or gets the class to use for resolving a class. Defaults to 
L<DBIx::Class::ClassResolver::Passthrough>, which returns whatever you give
it. See resolve_class below.

=cut

__PACKAGE__->mk_classdata('class_resolver' =>
                            'DBIx::Class::ClassResolver::PassThrough');

=head2 connection

  __PACKAGE__->connection($dsn, $user, $pass, $attrs);

Specifies the arguments that will be passed to DBI->connect(...) to
instantiate the class dbh when required.

=cut

sub connection {
  my ($class, @info) = @_;
  my $storage = DBIx::Class::Storage::DBI->new;
  $storage->connect_info(\@info);
  my $schema = bless({ storage => $storage }, 'DBIx::Class::Schema');
  $class->mk_classdata('schema_instance' => $schema);
}

=head2 txn_begin

Begins a transaction (does nothing if AutoCommit is off).

=cut

sub txn_begin { $_[0]->storage->txn_begin }

=head2 txn_commit

Commits the current transaction.

=cut

sub txn_commit { $_[0]->storage->txn_commit }

=head2 txn_rollback

Rolls back the current transaction.

=cut

sub txn_rollback { $_[0]->storage->txn_rollback }

{
  my $warn;

  sub resolve_class {
    warn "resolve_class deprecated as of 0.04999_02" unless $warn++;
    return shift->class_resolver->class(@_);
  }
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


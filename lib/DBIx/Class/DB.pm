package DBIx::Class::DB;

use base qw/DBIx::Class/;
use DBIx::Class::Storage::DBI;
use DBIx::Class::ClassResolver::PassThrough;
use DBI;

*dbi_commit = \&tx_commit;
*dbi_rollback = \&tx_rollback;

=head1 NAME 

DBIx::Class::DB - Simple DBIx::Class Database connection by class inheritance

=head1 SYNOPSIS

  package MyDB;

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components('DB');

  __PACKAGE__->connection('dbi:...', 'user', 'pass', \%attrs);

  package MyDB::MyTable;

  use base qw/MyDB/;
  __PACKAGE__->load_components('Core');

  ...

=head1 DESCRIPTION

This class provides a simple way of specifying a database connection.

=head1 METHODS

=head2 storage

Sets or gets the storage backend. Defaults to L<DBIx::Class::Storage::DBI>.

=head2 class_resolver

Sets or gets the class to use for resolving a class. Defaults to 
L<DBIx::Class::ClassResolver::Passthrough>, which returns whatever you give
it. See resolve_class below.

=cut

__PACKAGE__->mk_classdata('storage');
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
  $class->storage($storage);
}

=head2 tx_begin

Begins a transaction (does nothing if AutoCommit is off).

=cut

sub tx_commit { $_[0]->storage->tx_begin }

=head2 tx_commit

Commits the current transaction.

=cut

sub tx_commit { $_[0]->storage->tx_commit }

=head2 tx_rollback

Rolls back the current transaction.

=cut

sub tx_rollback { $_[0]->storage->tx_rollback }

sub resolve_class { return shift->class_resolver->class(@_); }

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


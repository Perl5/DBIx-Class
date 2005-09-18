package DBIx::Class::DB;

use base qw/Class::Data::Inheritable/;
use DBIx::Class::Storage::DBI;
use DBIx::Class::ClassResolver::PassThrough;
use DBI;

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

=over 4

=cut

__PACKAGE__->mk_classdata('storage');
__PACKAGE__->mk_classdata('class_resolver' =>
                            'DBIx::Class::ClassResolver::PassThrough');

=item connection

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

=item dbi_commit

  $class->dbi_commit;

Issues a commit again the current dbh

=cut

sub dbi_commit { $_[0]->storage->commit; }

=item dbi_rollback

  $class->dbi_rollback;

Issues a rollback again the current dbh

=cut

sub dbi_rollback { $_[0]->storage->rollback; }

sub resolve_class { return shift->class_resolver->class(@_); }

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


package DBIx::Class::DB;

use base qw/Class::Data::Inheritable/;
use DBI;

__PACKAGE__->mk_classdata('_dbi_connect_info');
__PACKAGE__->mk_classdata('_dbi_connect_package');
__PACKAGE__->mk_classdata('_dbh');

=head1 NAME 

DBIx::Class::DB - DBIx::Class Database connection

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the connection to the database

=head1 METHODS

=over 4

=cut

sub _get_dbh {
  my ($class) = @_;
  my $dbh;
  unless (($dbh = $class->_dbh) && $dbh->FETCH('Active') && $dbh->ping) {
    $class->_populate_dbh;
  }
  return $class->_dbh;
}

sub _populate_dbh {
  my ($class) = @_;
  my @info = @{$class->_dbi_connect_info || []};
  my $pkg = $class->_dbi_connect_package || $class;
  $pkg->_dbh($class->_dbi_connect(@info));
}

sub _dbi_connect {
  my ($class, @info) = @_;
  return DBI->connect(@info);
}

sub connection {
  my ($class, @info) = @_;
  $class->_dbi_connect_package($class);
  $class->_dbi_connect_info(\@info);
}

sub dbi_commit { $_[0]->_get_dbh->commit; }

sub dbi_rollback { $_[0]->_get_dbh->rollback; }

1;

=back

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


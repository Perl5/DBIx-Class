package DBIx::Class::DB;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('_dbi_connect_info');
__PACKAGE__->mk_classdata('_dbi_connect_package');
__PACKAGE__->mk_classdata('_dbh');

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

1;

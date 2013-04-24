package DBIx::Class::Storage::DBI::ODBC;
use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

use DBIx::Class::_Util 'modver_gt_or_eq';
use namespace::clean;

sub _rebless { shift->_determine_connector_driver('ODBC') }

# Whether or not we are connecting via the freetds ODBC driver
sub _using_freetds {
  my $self = shift;

  my $dsn = $self->_dbi_connect_info->[0];

  return 1 if (
    ( (! ref $dsn) and $dsn =~ /driver=FreeTDS/i)
      or
    ( ($self->_dbh_get_info('SQL_DRIVER_NAME')||'') =~ /tdsodbc/i )
  );

  return 0;
}

# Either returns the FreeTDS version via which we are connecting, 0 if can't
# be determined, or undef otherwise
sub _using_freetds_version {
  my $self = shift;
  return undef unless $self->_using_freetds;
  return $self->_dbh_get_info('SQL_DRIVER_VER') || 0;
}

sub _disable_odbc_array_ops {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  $DBD::ODBC::__DBIC_DISABLE_ARRAY_OPS_VIA__ ||= [ do {
    if( modver_gt_or_eq('DBD::ODBC', '1.35_01') ) {
      odbc_array_operations => 0;
    }
    elsif( modver_gt_or_eq('DBD::ODBC', '1.33_01') ) {
      odbc_disable_array_operations => 1;
    }
  }];

  if (my ($k, $v) = @$DBD::ODBC::__DBIC_DISABLE_ARRAY_OPS_VIA__) {
    $dbh->{$k} = $v;
  }
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC - Base class for ODBC drivers

=head1 DESCRIPTION

This class simply provides a mechanism for discovering and loading a sub-class
for a specific ODBC backend.  It should be transparent to the user.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:

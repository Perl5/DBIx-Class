package DBIx::Class::CDBICompat::Convenience;

use strict;
use warnings;

sub find_or_create {
  my $class    = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my ($exists) = $class->search($hash);
  return defined($exists) ? $exists : $class->create($hash);
}

sub retrieve_all {
  my ($class) = @_;
  return $class->retrieve_from_sql( '1' );
}

1;

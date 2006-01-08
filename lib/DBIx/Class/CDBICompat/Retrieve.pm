package DBIx::Class::CDBICompat::Retrieve;

use strict;
use warnings FATAL => 'all';


sub retrieve  {
  die "No args to retrieve" unless @_ > 1;
  shift->find(@_);
}

sub retrieve_from_sql {
  my ($class, $cond, @rest) = @_;
  $cond =~ s/^\s*WHERE//i;
  $class->search_literal($cond, @rest);
}

sub retrieve_all      { shift->search              }
sub count_all         { shift->count               }
  # Contributed by Numa. No test for this though.

1;

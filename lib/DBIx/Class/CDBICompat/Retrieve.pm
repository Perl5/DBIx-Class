package DBIx::Class::CDBICompat::Retrieve;

use strict;
use warnings FATAL => 'all';

sub retrieve          { shift->find(@_)            }
sub retrieve_all      { shift->search              }

sub retrieve_from_sql {
  my ($class, $cond, @rest) = @_;
  $cond =~ s/^\s*WHERE//i;
  $class->search_literal($cond, @rest);
}

sub count_all         { shift->count               }
  # Contributed by Numa. No test for this though.

1;

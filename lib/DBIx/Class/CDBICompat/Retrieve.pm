package DBIx::Class::CDBICompat::Retrieve;

use strict;
use warnings FATAL => 'all';

sub retrieve          { shift->find(@_)            }
sub retrieve_all      { shift->search_literal('1') }
sub retrieve_from_sql { shift->search_literal(@_)  }

sub count_all          { shift->count_literal('1')  }
  # Contributed by Numa. No test for this though.

1;

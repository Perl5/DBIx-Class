use strict;
use warnings;

use Test::More tests => 1;

use lib qw(t/lib);
eval {
  package DBICErrorTest::Schema;

  use base 'DBIx::Class::Schema';
  __PACKAGE__->load_classes('SourceWithError');
};

# Make sure the errors in components of resultset classes are reported right.
like($@, qr!syntax error at t/lib/DBICErrorTest/SyntaxError.pm!);

BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;

{
  package DBICTest::Foo;
  use base "DBIx::Class::Core";
}

throws_ok { DBICTest::Foo->new("urgh") } qr/must be a hashref/;

done_testing;

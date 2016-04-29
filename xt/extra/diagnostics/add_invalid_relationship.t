BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;

{
  local $TODO = "relationship checking needs fixing";
  # try to add a bogus relationship using the wrong cols
  throws_ok {
      DBICTest::Schema::Artist->add_relationship(
          tracks => 'DBICTest::Schema::Track',
          { 'foreign.cd' => 'self.cdid' }
      );
  } qr/Unknown column/, 'failed when creating a rel with invalid key, ok';
}

# another bogus relationship using no join condition
throws_ok {
    DBICTest::Schema::Artist->add_relationship( tracks => 'DBICTest::Track' );
} qr/join condition/, 'failed when creating a rel without join condition, ok';


done_testing;

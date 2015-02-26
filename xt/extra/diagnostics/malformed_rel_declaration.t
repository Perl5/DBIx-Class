use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest::Schema::Artist;

my $pkg = 'DBICTest::Schema::Artist';

for my $call (qw(has_many might_have has_one belongs_to)) {
  {
    local $TODO = 'stupid stupid heuristic - needs to die'
      if $call eq 'belongs_to';

    throws_ok {
      $pkg->$call( foos => 'nonexistent bars', { foo => 'self.artistid' } );
    } qr/Malformed relationship condition key 'foo': must be prefixed with 'foreign.'/,
    "Correct exception on $call with malformed foreign.";
  }

  throws_ok {
    $pkg->has_many( foos => 'nonexistent bars', { 'foreign.foo' => 'name' } );
  } qr/\QMalformed relationship condition value 'name': must be prefixed with 'self.'/,
  "Correct exception on $call with malformed self.";
}

done_testing;

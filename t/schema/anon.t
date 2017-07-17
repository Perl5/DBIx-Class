BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;
use Test::More;
use Test::Exception;


use DBICTest;

lives_ok (sub {
  DBICTest->init_schema()->resultset('Artist')->find({artistid => 1 })->update({name => 'anon test'});
}, 'Schema object not lost in chaining');

done_testing;

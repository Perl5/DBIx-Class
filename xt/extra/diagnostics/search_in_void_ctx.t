BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;


use DBICTest;

my $schema = DBICTest->init_schema(no_deploy => 1);

throws_ok {
  $schema->resultset('Artist')->search
} qr/\Qsearch is *not* a mutator/, 'Proper exception on search in void ctx';

done_testing;

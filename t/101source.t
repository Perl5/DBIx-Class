BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use warnings;
use strict;

use Test::More;
use Test::Exception;


use DBICTest;

my $schema = DBICTest->init_schema;

throws_ok {$schema->source()} qr/\Qsource() expects a source name/, 'Empty args for source caught';

done_testing();

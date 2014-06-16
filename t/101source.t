use warnings;
use strict;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema;

throws_ok {$schema->source()} qr/\Qsource() expects a source name/, 'Empty args for source caught';

done_testing();

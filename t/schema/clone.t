use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

ok ($schema->storage->connected, 'initialized schema connected');

my $clone = $schema->clone;
ok (!$clone->storage->connected, 'The clone storage is not connected');
cmp_ok ($clone->storage, 'ne', $schema->storage, 'Storage cloned with schema');

done_testing;

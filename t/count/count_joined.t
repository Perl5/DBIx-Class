use strict;
use warnings;

use Test::More;

use lib qw(t/lib);

use DBICTest;

plan tests => 1;

my $schema = DBICTest->init_schema();

my $cds = $schema->resultset("CD")->search({ cdid => 1 }, { join => { cd_to_producer => 'producer' } });
is($cds->count, 1, "extra joins do not explode single entity count");

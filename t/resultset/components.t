use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema;

isa_ok $schema->resultset('Artist'), 'A::Useless', 'Artist RS';
ok !$schema->resultset('CD')->isa('A::Useless'), 'CD RS is not A::Useless';

done_testing;

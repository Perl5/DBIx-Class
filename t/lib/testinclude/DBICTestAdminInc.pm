package DBICTestAdminInc;

use warnings;
use strict;

use base 'DBICTest::BaseSchema';

sub connect { exit 70 } # this is what the test will expect to see

1;

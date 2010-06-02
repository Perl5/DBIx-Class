package DBICTestAdminInc;
use base 'DBIx::Class::Schema';

sub connect { exit 70 } # this is what the test will expect to see

1;

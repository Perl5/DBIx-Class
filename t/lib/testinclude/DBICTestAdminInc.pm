package DBICTestAdminInc;
use base 'DBIx::Class::Schema';

our $loaded = 1;
sub connect { bless {}, __PACKAGE__ }

sub deploy { exit 70 }  # this is what the test will expect to see

1;

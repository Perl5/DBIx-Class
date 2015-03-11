use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

# Once upon a time there was a problem with a leaking $sth
# which in turn delayed the $dbh destruction, which in turn
# made the inode comaprison fire at the wrong time
# This simulates the problem without doing much else
for (1..2) {
  my $schema = DBICTest->init_schema( sqlite_use_file => 1 );
  $schema->storage->ensure_connected;
  isa_ok ($schema, 'DBICTest::Schema');
}

done_testing;


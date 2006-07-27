use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

plan tests => 2;

# Set up the "usual" sqlite for DBICTest
my $schema = DBICTest->init_schema;

# Make sure we're connected by doing something
my @art = $schema->resultset("Artist")->search({ }, { order_by => 'name DESC'});
cmp_ok(@art, '==', 3, "Three artists returned");

# Disconnect the dbh, and be sneaky about it
$schema->storage->_dbh->disconnect;

# Try the operation again - What should happen here is:
#   1. S::DBI blindly attempts the SELECT, which throws an exception
#   2. It catches the exception, checks ->{Active}/->ping, sees the disconnected state...
#   3. Reconnects, and retries the operation
#   4. Success!
my @art_two = $schema->resultset("Artist")->search({ }, { order_by => 'name DESC'});
cmp_ok(@art_two, '==', 3, "Three artists returned");

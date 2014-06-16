use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

##!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
## This test uses undocumented internal methods
## DO NOT USE THEM IN THE SAME MANNER
## They are subject to ongoing change
##!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# Set up the "usual" sqlite for DBICTest
my $schema = DBICTest->init_schema;
my $dbh = $schema->storage->_get_dbh;

my $sth_one = $schema->storage->_prepare_sth($dbh, 'SELECT 42');
my $sth_two = $schema->storage->_prepare_sth($dbh, 'SELECT 42');
$schema->storage->disable_sth_caching(1);
my $sth_three = $schema->storage->_prepare_sth($dbh, 'SELECT 42');

ok($sth_one == $sth_two, "statement caching works");
ok($sth_two != $sth_three, "disabling statement caching works");

done_testing;

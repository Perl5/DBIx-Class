use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();
$schema->storage->sql_maker->quote_char('"');

my $rs = $schema->resultset ('Artist');
my $last_obj = $rs->search ({}, { order_by => { -desc => 'artistid' }, rows => 1})->single;
my $last_id = $last_obj ? $last_obj->artistid : 0;

my $obj;
$schema->is_executed_sql_bind( sub {
  $obj = $rs->create ({})
}, [[
  'INSERT INTO "artist" DEFAULT VALUES'
]], 'Default-value insert correct SQL' );

ok ($obj, 'Insert defaults ( $rs->create ({}) )' );

# this should be picked up without calling the DB again
is ($obj->artistid, $last_id + 1, 'Autoinc PK works');

# for this we need to refresh
$obj->discard_changes;
is ($obj->rank, 13, 'Default value works');

done_testing;

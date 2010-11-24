use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::DebugObj;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();
$schema->storage->sql_maker->quote_char('"');

my $rs = $schema->resultset ('Artist');
my $last_obj = $rs->search ({}, { order_by => { -desc => 'artistid' }, rows => 1})->single;
my $last_id = $last_obj ? $last_obj->artistid : 0;


my ($sql, @bind);
my $orig_debugobj = $schema->storage->debugobj;
my $orig_debug = $schema->storage->debug;

$schema->storage->debugobj (DBIC::DebugObj->new (\$sql, \@bind) );
$schema->storage->debug (1);

my $obj;
lives_ok { $obj = $rs->create ({}) } 'Default insert successful';

$schema->storage->debugobj ($orig_debugobj);
$schema->storage->debug ($orig_debug);

is_same_sql_bind (
  $sql,
  \@bind,
  'INSERT INTO "artist" DEFAULT VALUES',
  [],
  'Default-value insert correct SQL',
);

ok ($obj, 'Insert defaults ( $rs->create ({}) )' );

# this should be picked up without calling the DB again
is ($obj->artistid, $last_id + 1, 'Autoinc PK works');

# for this we need to refresh
$obj->discard_changes;
is ($obj->rank, 13, 'Default value works');

done_testing;

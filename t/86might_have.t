use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $queries;
$schema->storage->debugcb( sub{ $queries++ } );
my $sdebug = $schema->storage->debug;

plan tests => 2;

my $cd = $schema->resultset("CD")->find(1);
$cd->title('test');

# SELECT count
$queries = 0;
$schema->storage->debug(1);

$cd->update;

is($queries, 1, 'liner_notes (might_have) not prefetched - do not load 
liner_notes on update');

$schema->storage->debug($sdebug);


my $cd2 = $schema->resultset("CD")->find(2, {prefetch => 'liner_notes'});
$cd2->title('test2');

# SELECT count
$queries = 0;
$schema->storage->debug(1);

$cd2->update;

is($queries, 1, 'liner_notes (might_have) prefetched - do not load 
liner_notes on update');

$schema->storage->debug($sdebug);

$| = 1;
use warnings;
use strict;

use Test::More;

use lib 't/cdbi/testlib';
use DBIC::Test::SQLite (); # this will issue the necessary SKIPs on missing reqs

eval { require Time::Piece::MySQL }
  or plan skip_all => 'Time::Piece::MySQL required for this test';

use_ok ('Log');

package main;

my $log = Log->insert( { message => 'initial message' } );
ok eval { $log->datetime_stamp }, "Have datetime";
diag $@ if $@;

$log->message( 'a revised message' );
$log->update;
ok eval { $log->datetime_stamp }, "Have datetime after update";
diag $@ if $@;

done_testing;

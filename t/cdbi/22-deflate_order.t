$| = 1;
use strict;

use Test::More;

eval "use DBIx::Class::CDBICompat; use Time::Piece::MySQL;";
if ($@) {
    plan (skip_all => "Time::Piece::MySQL, Class::Trigger and DBIx::ContextualFetch required: $@");
}

use lib 't/cdbi/testlib';
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

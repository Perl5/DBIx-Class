BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => qw( cdbicompat test_rdbms_mysql Time::Piece::MySQL>=0 );

$| = 1;
use warnings;
use strict;

use Test::More;

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

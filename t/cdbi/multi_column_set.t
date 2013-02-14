use strict;
use warnings;
use Test::More;
use lib 't/cdbi/testlib';

{
    package Thing;

    use base 'DBIC::Test::SQLite';

    Thing->columns(TEMP => qw[foo bar baz]);
    Thing->columns(All  => qw[some real stuff]);
}

my $thing = Thing->construct({ foo => 23, some => 42, baz => 99 });
$thing->set( foo => "wibble", some => "woosh" );
is $thing->foo, "wibble";
is $thing->some, "woosh";
is $thing->baz, 99;

$thing->discard_changes;

done_testing;

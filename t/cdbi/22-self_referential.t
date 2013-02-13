use strict;
use warnings;
use Test::More;

use lib 't/cdbi/testlib';
use Actor;
use ActorAlias;
Actor->has_many( aliases => [ 'ActorAlias' => 'alias' ] );

my $first  = Actor->create( { Name => 'First' } );
my $second = Actor->create( { Name => 'Second' } );

ActorAlias->create( { actor => $first, alias => $second } );

my @aliases = $first->aliases;

is( scalar @aliases, 1, 'proper number of aliases' );
is( $aliases[ 0 ]->name, 'Second', 'proper alias' );

done_testing;

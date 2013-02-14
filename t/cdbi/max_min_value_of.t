use strict;
use warnings;
use Test::More;

#----------------------------------------------------------------------
# Test database failures
#----------------------------------------------------------------------

use lib 't/cdbi/testlib';
use Film;

Film->create({
    title => "Bad Taste",
    numexplodingsheep => 10,
});

Film->create({
    title => "Evil Alien Conquerers",
    numexplodingsheep => 2,
});

is( Film->maximum_value_of("numexplodingsheep"), 10 );
is( Film->minimum_value_of("numexplodingsheep"), 2  );

done_testing;

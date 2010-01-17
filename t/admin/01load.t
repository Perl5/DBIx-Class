use strict;
use warnings;

use Test::More;


BEGIN {
    eval "use DBIx::Class::Admin";
    plan skip_all => "Deps not installed: $@" if $@;
}

use_ok 'DBIx::Class::Admin';


done_testing;

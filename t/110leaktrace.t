use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

BEGIN {
    eval "use Test::LeakTrace";
    plan 'skip_all' => 'Test::LeakTrace required for this tests' if $@;
}

my $schema = DBICTest->init_schema();

plan tests => 1;

my $artist_rs = $schema->resultset('Artist')->search({},{order_by=>'me.artistid'});
no_leaks_ok {
    my @artists = $artist_rs->all;
};

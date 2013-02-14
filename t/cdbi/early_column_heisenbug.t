use strict;
use warnings;

use Test::More;

use lib 't/cdbi/testlib';
use DBIC::Test::SQLite (); # this will issue the necessary SKIPs on missing reqs

{
    package Thing;
    use base qw(DBIx::Class::CDBICompat);
}

{
    package Stuff;
    use base qw(DBIx::Class::CDBICompat);
}

# There was a bug where looking at a column group before any were
# set would cause them to be shared across classes.
is_deeply [Stuff->columns("Essential")], [];
Thing->columns(Essential => qw(foo bar baz));
is_deeply [Stuff->columns("Essential")], [];

done_testing;

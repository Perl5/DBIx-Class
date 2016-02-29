BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'cdbicompat';

use strict;
use warnings;

use Test::More;

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

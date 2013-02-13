use strict;
use warnings;
use Test::More;

use lib 't/cdbi/testlib';
use DBIC::Test::SQLite (); # this will issue the necessary SKIPs on missing reqs

package Foo;

use base qw(DBIx::Class::CDBICompat);

eval {
    Foo->table("foo");
    Foo->columns(Essential => qw(foo bar));
    #Foo->has_a( bar => "This::Does::Not::Exist::Yet" );
};
#::is $@, '';
::is(Foo->table, "foo");
::is_deeply [sort map lc, Foo->columns], [sort map lc, qw(foo bar)];

::done_testing;

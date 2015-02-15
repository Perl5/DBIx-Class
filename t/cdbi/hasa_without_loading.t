use DBIx::Class::Optional::Dependencies -skip_all_without => 'cdbicompat';

use strict;
use warnings;

use Test::More;

use lib 't/cdbi/testlib';

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

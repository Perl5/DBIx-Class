#!/usr/bin/perl -w
#Simon Ilyushchenko, 12/05/05
#Testing the case when we try to inject into @ISA a class that's already a parent of the target class.

use strict;
use Test::More tests => 2;
use MRO::Compat;

{
package AAA;

use base "DBIx::Class::Core";

package BBB;

use base 'AAA';

#Injecting a direct parent.
__PACKAGE__->inject_base( __PACKAGE__, 'AAA' );


package CCC;

use base 'AAA';

#Injecting an indirect parent.
__PACKAGE__->inject_base( __PACKAGE__, 'DBIx::Class::Core' );
}

eval { mro::get_linear_isa('BBB'); };
ok (! $@, "Correctly skipped injecting a direct parent of class BBB");

eval { mro::get_linear_isa('CCC'); };
ok (! $@, "Correctly skipped injecting an indirect parent of class BBB");

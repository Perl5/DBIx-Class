use strict;
use warnings;
use Test::More;

use lib 't/cdbi/testlib';
use DBIC::Test::SQLite;

package A;
@A::ISA = qw(DBIx::Class::CDBICompat);
__PACKAGE__->columns(Primary => 'id');

package A::B;
@A::B::ISA = 'A';
__PACKAGE__->columns(All => qw(id b1));

package A::C;
@A::C::ISA = 'A';
__PACKAGE__->columns(All => qw(id c1 c2 c3));

package main;
is join (' ', sort A->columns),    'id',          "A columns";
is join (' ', sort A::B->columns), 'b1 id',       "A::B columns";
is join (' ', sort A::C->columns), 'c1 c2 c3 id', "A::C columns";

done_testing;

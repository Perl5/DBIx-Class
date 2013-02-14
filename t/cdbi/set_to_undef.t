use strict;
use warnings;
use Test::More;

use lib 't/cdbi/testlib';
use DBIC::Test::SQLite (); # this will issue the necessary SKIPs on missing reqs

BEGIN {
  eval { require DateTime; DateTime->VERSION(0.55) }
    or plan skip_all => 'DateTime 0.55 required for this test';
}


# Don't use Test::NoWarnings because of an unrelated DBD::SQLite warning.
my @warnings;
local $SIG{__WARN__} = sub {
    push @warnings, @_;
};

{
    package Thing;

    use base 'DBIC::Test::SQLite';

    Thing->columns(All  => qw[thing_id this that date]);
}

my $thing = Thing->construct({ thing_id => 23, this => 42 });
$thing->set( this => undef );
is $thing->get( "this" ), undef, 'undef set';
$thing->discard_changes;

is @warnings, 0, 'no warnings';

done_testing;

use strict;
use Test::More;
use lib 't/cdbi/testlib';

BEGIN {
  eval "use DBIx::Class::CDBICompat;use DateTime 0.55;";
  plan skip_all => "DateTime 0.55, Class::Trigger and DBIx::ContextualFetch required: $@"
    if $@;
  plan tests => 2;
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

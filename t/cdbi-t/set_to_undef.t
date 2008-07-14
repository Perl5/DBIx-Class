#!/usr/bin/perl -w

use strict;
use Test::More;

BEGIN {
  eval "use DBIx::Class::CDBICompat;";
  plan skip_all => "Class::Trigger and DBIx::ContextualFetch required: $@"
    if $@;
  plan skip_all => "DateTime required" unless eval { require DateTime };
  plan tests => 1;
}

use Test::NoWarnings;

{
    package Thing;

    use base 'DBIx::Class::Test::SQLite';

    Thing->columns(All  => qw[thing_id this that date]);
}

my $thing = Thing->construct({ thing_id => 23, this => 42 });
$thing->set( this => undef );
$thing->discard_changes;

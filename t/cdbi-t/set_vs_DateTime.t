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

{
    package Thing;

    use base 'DBIx::Class::Test::SQLite';

    Thing->columns(All  => qw[thing_id this that date]);
}

my $thing = Thing->construct({ thing_id => 23, date => "01-02-1994" });
eval {
  $thing->set( date => DateTime->now );
};
is $@, '';

$thing->discard_changes;

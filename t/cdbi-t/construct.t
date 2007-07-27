#!/usr/bin/perl -w

use strict;
use Test::More;

BEGIN {
  eval "use DBIx::Class::CDBICompat;";
  plan $@ ? (skip_all => "Class::Trigger and DBIx::ContextualFetch required: $@")
          : (tests=> 4);
}

INIT {
    use lib 't/testlib';
    use Film;
}

Film->insert({
    Title     => "Breaking the Waves",
    Director  => 'Lars von Trier',
    Rating    => 'R'
});

my $film = Film->construct({
    Title     => "Breaking the Waves",
    Director  => 'Lars von Trier',
});

isa_ok $film, "Film";
is $film->title, "Breaking the Waves";
is $film->director, "Lars von Trier";
is $film->rating, "R", "constructed objects can get missing data from the db";
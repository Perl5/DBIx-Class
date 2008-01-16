#!/usr/bin/perl -w

use strict;
use Test::More;
use Test::Warn;

BEGIN {
  eval "use DBIx::Class::CDBICompat;";
  plan $@ ? (skip_all => "Class::Trigger and DBIx::ContextualFetch required: $@")
          : (tests=> 6);
}

use lib 't/testlib';
use Film;

my $waves = Film->insert({
    Title     => "Breaking the Waves",
    Director  => 'Lars von Trier',
    Rating    => 'R'
});

warnings_like {
    is $waves->{title}, $waves->Title, "columns can be accessed as hashes";
} qr{^Column 'title' of 'Film/$waves' was accessed as a hash at .*$};

$waves->Rating("G");

warnings_like {
    is $waves->{rating}, "G", "updating via the accessor updates the hash";
} qr{^Column 'rating' of 'Film/$waves' was accessed as a hash .*$};

$waves->{rating} = "PG";

warnings_like {
    $waves->update;
} qr{^Column 'rating' of 'Film/$waves' was updated as a hash .*$};

my @films = Film->search( Rating => "PG", Title => "Breaking the Waves" );
is @films, 1, "column updated as hash was saved";

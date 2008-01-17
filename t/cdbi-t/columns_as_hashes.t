#!/usr/bin/perl -w

use strict;
use Test::More;
use Test::Warn;

BEGIN {
  eval "use DBIx::Class::CDBICompat;";
  plan $@ ? (skip_all => "Class::Trigger and DBIx::ContextualFetch required: $@")
          : (tests=> 9);
}

use lib 't/testlib';
use Film;

my $waves = Film->insert({
    Title     => "Breaking the Waves",
    Director  => 'Lars von Trier',
    Rating    => 'R'
});

local $ENV{DBIC_CDBICOMPAT_HASH_WARN} = 1;

warnings_like {
    my $rating = $waves->{rating};
    $waves->Rating("PG");
    is $rating, "R", 'evaluation of column value is not deferred';
} qr{^Column 'rating' of 'Film/$waves' was fetched as a hash at \Q$0};

warnings_like {
    is $waves->{title}, $waves->Title, "columns can be accessed as hashes";
} qr{^Column 'title' of 'Film/$waves' was fetched as a hash at\b};

$waves->Rating("G");

warnings_like {
    is $waves->{rating}, "G", "updating via the accessor updates the hash";
} qr{^Column 'rating' of 'Film/$waves' was fetched as a hash at\b};


warnings_like {
    $waves->{rating} = "PG";
} qr{^Column 'rating' of 'Film/$waves' was stored as a hash at\b};

$waves->update;
my @films = Film->search( Rating => "PG", Title => "Breaking the Waves" );
is @films, 1, "column updated as hash was saved";


warning_is {
    local $ENV{DBIC_CDBICOMPAT_HASH_WARN} = 0;
    $waves->{rating}
} '', 'DBIC_CDBICOMPAT_HASH_WARN controls warnings';
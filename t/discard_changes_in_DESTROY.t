#!/usr/bin/perl -w

use strict;
use Test::More;

BEGIN {
  eval "use DBIx::Class::CDBICompat;";
  plan $@ ? (skip_all => "Class::Trigger and DBIx::ContextualFetch required: $@")
          : (tests=> 1);
}

INIT {
    use lib 't/testlib';
    use Film;
}

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_; };
    {
        # Test that this doesn't cause infinite recursion.
        local *Film::DESTROY;
        local *Film::DESTROY = sub { $_[0]->discard_changes };
        
        my $film = Film->insert({ Title => "Eegah!" });
        $film->director("Arch Hall Sr.");
    }
    is_deeply \@warnings, [];
}
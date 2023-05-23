package #hide from pause
  DBICTest::BaseResultSet;

use strict;
use warnings;

BEGIN {
  my @subclassing = qw(DBICTest::Base DBIx::Class::ResultSet);

  if( ! $ENV{DBICTEST_MOOIFIED_RESULTSETS} ) {
    # plain old vanilla base.pm
    require base;
    base->import(@subclassing);
  }
  else {
    # do a string eval to make sure Moo doesn't get confused
    require Carp;
    eval <<'EOM'


use Moo;
extends @subclassing;

# ::RS::new() expects my ($class, $rsrc, $args) = @_
# Moo(se) expects a single hashref ( $args ), and makes it mandatory
#
# Ensure that unless we are called from a test - DBIC always fills it in
sub BUILDARGS {
  if(
    ! defined $_[2]
      and
    # not a direct call from a test file
    (caller(1))[1] !~ m{ (?: ^ | \/ | \\ ) t [\/\\] .+ \.t $ }x
  ) {
    $Carp::CarpLevel += 2;
    Carp::confess( "...::ResultSet->new() called without supplying an ( empty ) hashref as argument: this fails with Moo(se) and incomplete BUILDARGS. Problematic stacktrace begins" );
  }

  $_[2] || {};
}


EOM

  }
}

sub all_hri {
  return [ shift->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' })->all ];
}

1;

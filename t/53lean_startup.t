# Use a require override instead of @INC munging (less common)
# Do the override as early as possible so that CORE::require doesn't get compiled away
# We will add the hook in a bit, got to load some regular stuff

my $test_hook;
BEGIN {
  unshift @INC, 't/lib';
  require DBICTest::Util::OverrideRequire;

  DBICTest::Util::OverrideRequire::override_global_require( sub {
    my $res = $_[0]->();
    $test_hook->($_[1]) if $test_hook;
    return $res;
  });
}

use strict;
use warnings;
use Test::More;
use Data::Dumper;

# Package::Stash::XS is silly and fails if a require hook contains regular
# expressions on perl < 5.8.7. Load the damned thing if the case
BEGIN {
  require Package::Stash if $] < 5.008007;
}

my $expected_core_modules;

BEGIN {
  $expected_core_modules = { map { $_ => 1 } qw/
    strict
    warnings

    base
    mro
    overload

    B
    locale

    namespace::clean
    Try::Tiny
    Sub::Name

    Scalar::Util
    List::Util
    Hash::Merge
    Data::Compare

    DBI
    SQL::Abstract

    Carp

    Class::Accessor::Grouped
    Class::C3::Componentised
  /, $] < 5.010 ? ( 'Class::C3', 'MRO::Compat' ) : () }; # this is special-cased in DBIx/Class.pm

  $test_hook = sub {

    my $req = $_[0];
    $req =~ s/\.pm$//;
    $req =~ s/\//::/g;

    return if $req =~ /^DBIx::Class|^DBICTest::/;

    my $up = 1;
    my @caller;
    do { @caller = caller($up++) } while (
      @caller and (
        # exclude our test suite, known "module require-rs" and eval frames
        $caller[1] =~ /^ t [\/\\] /x
          or
        $caller[0] =~ /^ (?: base | parent | Class::C3::Componentised | Module::Inspector) $/x
          or
        $caller[3] eq '(eval)',
      )
    );

    # exclude everything where the current namespace does not match the called function
    # (this works around very weird XS-induced require callstack corruption)
    if (
      !$expected_core_modules->{$req}
        and
      @caller
        and
      $caller[0] =~ /^DBIx::Class/
        and
      (caller($up))[3] =~ /\Q$caller[0]/
    ) {
      fail ("Unexpected require of '$req' by $caller[0] ($caller[1] line $caller[2])");

      if ($ENV{TEST_VERBOSE}) {
        my ($i, @stack) = 1;
        while (my @f = caller($i++) ) {
          push @stack, \@f;
        }
        diag Dumper(\@stack);
      }
    }
  };
}

use lib 't/lib';
use DBICTest;

# these envvars bring in more stuff
delete $ENV{$_} for qw/
  DBICTEST_SQLT_DEPLOY
  DBIC_TRACE
/;

my $schema = DBICTest->init_schema;
is ($schema->resultset('Artist')->next->name, 'Caterwauler McCrae');

# check if anything we were expecting didn't actually load
my $nl;
for (keys %$expected_core_modules) {
  my $mod = "$_.pm";
  $mod =~ s/::/\//g;
  unless ($INC{$mod}) {
    my $err = sprintf "Expected DBIC core module %s never loaded - %s needs adjustment", $_, __FILE__;
    if (DBICTest::RunMode->is_smoker or DBICTest::RunMode->is_author) {
      fail ($err)
    }
    else {
      diag "\n" unless $nl++;
      diag $err;
    }
  }
}

done_testing;

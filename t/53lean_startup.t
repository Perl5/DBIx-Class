# Use a require override instead of @INC munging (less common)
# Do the override as early as possible so that CORE::require doesn't get compiled away
# We will replace $req_override in a bit

my $test_hook;
BEGIN {
  $test_hook = sub {}; # noop at first
  *CORE::GLOBAL::require = sub {
    $test_hook->(@_);
    CORE::require($_[0]);
  };
}

use strict;
use warnings;
use Test::More;
use Data::Dumper;

BEGIN {
  my $core_modules = { map { $_ => 1 } qw/
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
      !$core_modules->{$req}
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

done_testing;

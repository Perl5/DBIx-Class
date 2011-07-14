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

BEGIN {
  my $core_modules = { map { $_ => 1 } qw/
    strict
    warnings
    vars

    base
    parent
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

    DBI
    SQL::Abstract

    Carp

    Class::Accessor::Grouped
    Class::C3::Componentised

    Data::Compare
  /, $] < 5.010 ? 'MRO::Compat' : () };

  $test_hook = sub {

    my $req = $_[0];
    $req =~ s/\.pm$//;
    $req =~ s/\//::/g;

    return if $req =~ /^DBIx::Class|^DBICTest::Schema/;

    my $up = 1;
    my @caller;
    do { @caller = caller($up++) } while (
      @caller and (
        $caller[0] =~ /^ (?: base | parent | Class::C3::Componentised | Module::Inspector) $/x
          or
        $caller[1] =~ / \( eval \s \d+ \) /x
      )
    );

    if ( $caller[0] =~ /^DBIx::Class/) {
      fail ("Unexpected require of '$req' by $caller[0] ($caller[1] line $caller[2])")
        unless $core_modules->{$req};
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

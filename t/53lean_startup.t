# Use a require override instead of @INC munging (less common)
# Do the override as early as possible so that CORE::require doesn't get compiled away

my ($initial_inc_contents, $expected_dbic_deps, $require_sites);
BEGIN {
  # these envvars *will* bring in more stuff than the baseline
  delete @ENV{qw(DBICTEST_SQLT_DEPLOY DBIC_TRACE)};

  unshift @INC, 't/lib';
  require DBICTest::Util::OverrideRequire;

  DBICTest::Util::OverrideRequire::override_global_require( sub {
    my $res = $_[0]->();

    my $req = $_[1];
    $req =~ s/\.pm$//;
    $req =~ s/\//::/g;

    my $up = 0;
    my @caller;
    do { @caller = caller($up++) } while (
      @caller and (
        # exclude our test suite, known "module require-rs" and eval frames
        $caller[1] =~ /^ t [\/\\] /x
          or
        $caller[0] =~ /^ (?: base | parent | Class::C3::Componentised | Module::Inspector | Module::Runtime ) $/x
          or
        $caller[3] eq '(eval)',
      )
    );

    push @{$require_sites->{$req}}, "$caller[1] line $caller[2]"
      if @caller;

    return $res if $req =~ /^DBIx::Class|^DBICTest::/;

    # exclude everything where the current namespace does not match the called function
    # (this works around very weird XS-induced require callstack corruption)
    if (
      !$initial_inc_contents->{$req}
        and
      !$expected_dbic_deps->{$req}
        and
      @caller
        and
      $caller[0] =~ /^DBIx::Class/
        and
      (caller($up))[3] =~ /\Q$caller[0]/
    ) {
      CORE::require('Test/More.pm');
      Test::More::fail ("Unexpected require of '$req' by $caller[0] ($caller[1] line $caller[2])");

      if ($ENV{TEST_VERBOSE}) {
        CORE::require('DBICTest/Util.pm');
        Test::More::diag( 'Require invoked' .  DBICTest::Util::stacktrace() );
      }
    }

    return $res;
  });
}

use strict;
use warnings;
use Test::More;

use lib 't/dqlib';

BEGIN {
  plan skip_all => 'A defined PERL5OPT may inject extra deps crashing this test'
    if $ENV{PERL5OPT};

  plan skip_all => 'Dependency load patterns are radically different before perl 5.10'
    if $] < 5.010;

  # add what we loaded so far
  for (keys %INC) {
    my $mod = $_;
    $mod =~ s/\.pm$//;
    $mod =~ s!\/!::!g;
    $initial_inc_contents->{$mod} = 1;
  }
}

#######
### This is where the test starts
#######

# checking base schema load, no storage no connection
{
  register_lazy_loadable_requires(qw(
    B
    constant
    overload

    base
    Devel::GlobalDestruction
    mro

    Carp
    namespace::clean
    Try::Tiny
    Sub::Name

    Scalar::Util
    List::Util
    Data::Compare

    Class::Accessor::Grouped
    Class::C3::Componentised

    Module::Runtime
    Data::Query::Constants
    Data::Query::ExprHelpers
  ));

  require DBICTest::Schema;
  assert_no_missing_expected_requires();
}

# check schema/storage instantiation with no connect
{
  register_lazy_loadable_requires(qw(
    Moo
    Sub::Quote
    Context::Preserve
  ));

  my $s = DBICTest::Schema->connect('dbi:SQLite::memory:');
  ok (! $s->storage->connected, 'no connection');
  assert_no_missing_expected_requires();
}

# do something (deploy, insert)
{
  register_lazy_loadable_requires(qw(
    DBI
    SQL::Abstract
    Hash::Merge
  ));

  my $s = DBICTest::Schema->connect('dbi:SQLite::memory:');
  $s->storage->dbh_do(sub {
    $_[1]->do('CREATE TABLE artist (
      "artistid" INTEGER PRIMARY KEY NOT NULL,
      "name" varchar(100),
      "rank" integer NOT NULL DEFAULT 13,
      "charfield" char(10)
    )');
  });

  my $art = $s->resultset('Artist')->create({ name => \[ '?' => 'foo'], rank => 42 });
  $art->discard_changes;
  $art->update({ rank => 69, name => 'foo' });
  assert_no_missing_expected_requires();
}

# and do full populate() as well, just in case - shouldn't add new stuff
{
  local $ENV{DBICTEST_SQLITE_REVERSE_DEFAULT_ORDER};
  require DBICTest;
  my $s = DBICTest->init_schema;
  is ($s->resultset('Artist')->find(1)->name, 'Caterwauler McCrae');
  assert_no_missing_expected_requires();
}

done_testing;

sub register_lazy_loadable_requires {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  for my $mod (@_) {
    (my $modfn = "$mod.pm") =~ s!::!\/!g;
    fail(join "\n",
      "Module $mod already loaded by require site(s):",
      (map { "\t$_" } @{$require_sites->{$mod}}),
      '',
    ) if $INC{$modfn} and !$initial_inc_contents->{$mod};

    $expected_dbic_deps->{$mod}++
  }
}

# check if anything we were expecting didn't actually load
sub assert_no_missing_expected_requires {
  my $nl;
  for my $mod (keys %$expected_dbic_deps) {
    (my $modfn = "$mod.pm") =~ s/::/\//g;
    unless ($INC{$modfn}) {
      my $err = sprintf "Expected DBIC core dependency '%s' never loaded - %s needs adjustment", $mod, __FILE__;
      if (DBICTest::RunMode->is_smoker or DBICTest::RunMode->is_author) {
        fail ($err)
      }
      else {
        diag "\n" unless $nl->{$mod}++;
        diag $err;
      }
    }
  }
  pass(sprintf 'All modules expected at %s line %s loaded by DBIC: %s',
    __FILE__,
    (caller(0))[2],
    join (', ', sort keys %$expected_dbic_deps ),
  ) unless $nl;
}

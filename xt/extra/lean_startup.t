# Use a require override instead of @INC munging (less common)
# Do the override as early as possible so that CORE::require doesn't get compiled away

BEGIN {
  if ( $ENV{RELEASE_TESTING} ) {
    require warnings and warnings->import;
    require strict and strict->import;
  }
}

my ($initial_inc_contents, $expected_dbic_deps, $require_sites, %stack);
BEGIN {
  unshift @INC, 't/lib';
  require DBICTest::Util::OverrideRequire;

  DBICTest::Util::OverrideRequire::override_global_require( sub {
    my $res = $_[0]->();

    return $res if $stack{neutralize_override};

    my $req = $_[1];
    $req =~ s/\.pm$//;
    $req =~ s/\//::/g;

    my $up = 0;
    my @caller;
    do { @caller = CORE::caller($up++) } while (
      @caller and (
        # exclude our test suite, known "module require-rs" and eval frames
        $caller[1] =~ / (?: \A | [\/\\] ) x?t [\/\\] /x
          or
        $caller[0] =~ /^ (?: base | parent | Class::C3::Componentised | Module::Inspector | Module::Runtime ) $/x
          or
        $caller[3] eq '(eval)',
      )
    );

    push @{$require_sites->{$req}}, "$caller[1] line $caller[2]"
      if @caller;

    return $res if $req =~ /^DBIx::Class|^DBICTest::/;

    # Some modules have a bare 'use $perl_version' as the first statement
    # Since the use() happens before 'package' had a chance to switch
    # the namespace, the shim thinks DBIC* tried to require this
    return $res if $req =~ /^v?[0-9.]$/;

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
      (CORE::caller($up))[3] =~ /\Q$caller[0]/
    ) {
      local $stack{neutralize_override} = 1;

      do 1 while CORE::caller(++$up);

      require('Test/More.pm');
      local $Test::Builder::Level = $up + 1;
      Test::More::fail ("Unexpected require of '$req' by $caller[0] ($caller[1] line $caller[2])");

      require('DBICTest/Util.pm');
      Test::More::diag( 'Require invoked' .  DBICTest::Util::stacktrace() );
    }

    return $res;
  });
}

use strict;
use warnings;
use Test::More;

BEGIN {
  plan skip_all => 'A defined PERL5OPT may inject extra deps crashing this test'
    if $ENV{PERL5OPT};

  plan skip_all => 'Presence of sitecustomize.pl may inject extra deps crashing this test'
    if grep { $_ =~ m| \/ sitecustomize\.pl $ |x } keys %INC;

  plan skip_all => 'Dependency load patterns are radically different before perl 5.10'
    if "$]" < 5.010;

  # these envvars *will* bring in more stuff than the baseline
  delete @ENV{qw(
    DBIC_TRACE
    DBIC_SHUFFLE_UNORDERED_RESULTSETS
    DBICTEST_SQLT_DEPLOY
    DBICTEST_SQLITE_REVERSE_DEFAULT_ORDER
    DBICTEST_VIA_REPLICATED
    DBICTEST_DEBUG_CONCURRENCY_LOCKS
  )};

  $ENV{DBICTEST_ANFANG_DEFANG} = 1;

  # make sure extras do not load even when this is set
  $ENV{PERL_STRICTURES_EXTRA} = 1;

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
    Sub::Defer
    Sub::Quote
    attributes
    File::Spec

    Scalar::Util
    Storable

    Class::Accessor::Grouped
    Class::C3::Componentised
  ));

  require DBIx::Class::Schema;
  assert_no_missing_expected_requires();
}

# check schema/storage instantiation with no connect
{
  register_lazy_loadable_requires(qw(
    Moo
    Moo::Object
    Method::Generate::Accessor
    Method::Generate::Constructor
    Context::Preserve
    SQL::Abstract
  ));

  my $s = DBIx::Class::Schema->connect('dbi:SQLite::memory:');
  ok (! $s->storage->connected, 'no connection');
  assert_no_missing_expected_requires();
}

# do something (deploy, insert)
{
  register_lazy_loadable_requires(qw(
    DBI
    Hash::Merge
  ));

  {
    eval <<'EOP' or die $@;

  package DBICTest::Result::Artist;

  use warnings;
  use strict;

  use base 'DBIx::Class::Core';

  __PACKAGE__->table("artist");

  __PACKAGE__->add_columns(
    artistid => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
    name => {
      data_type => 'varchar',
      size      => 100,
      is_nullable => 1,
    },
    rank => {
      data_type => 'integer',
      default_value => 13,
    },
    charfield => {
      data_type => 'char',
      size => 10,
      is_nullable => 1,
    },
  );

  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->add_unique_constraint(['name']);
  __PACKAGE__->add_unique_constraint(u_nullable => [qw/charfield rank/]);

  1;

EOP
  }

  my $s = DBIx::Class::Schema->connect('dbi:SQLite::memory:');

  $s->register_class( Artist => 'DBICTest::Result::Artist' );

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
  $s->resultset('Artist')->all;
  assert_no_missing_expected_requires();
}


# and do full DBICTest based populate() as well, just in case - shouldn't add new stuff
{
  # DBICTest needs File::Spec, but older versions of Storable load it alread
  # Instead of adding a contrived conditional, just preempt the testing entirely
  require File::Spec;

  require DBICTest;
  DBICTest->import;

  my $s = DBICTest->init_schema;
  is ($s->resultset('Artist')->find(1)->name, 'Caterwauler McCrae', 'Expected find() result');
}

done_testing;
# one final quiet guard to run at all times
END { assert_no_missing_expected_requires('quiet') };

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
  my $quiet = shift;

  for my $mod (keys %$expected_dbic_deps) {
    (my $modfn = "$mod.pm") =~ s/::/\//g;
    fail sprintf (
      "Expected DBIC core dependency '%s' never loaded - %s needs adjustment",
      $mod,
      __FILE__
    ) unless $INC{$modfn};
  }

  pass(sprintf 'All modules expected at %s line %s loaded by DBIC: %s',
    __FILE__,
    (caller(0))[2],
    join (', ', sort keys %$expected_dbic_deps ),
  ) unless $quiet;
}

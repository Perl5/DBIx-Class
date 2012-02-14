# work around brain damage in PPerl (yes, it has to be a global)
$SIG{__WARN__} = sub {
  warn @_ unless $_[0] =~ /\QUse of "goto" to jump into a construct is deprecated/
} if ($ENV{DBICTEST_IN_PERSISTENT_ENV});

# the persistent environments run with this flag first to see if
# we will run at all (e.g. it will fail if $^X doesn't match)
exit 0 if $ENV{DBICTEST_PERSISTENT_ENV_BAIL_EARLY};

# Do the override as early as possible so that CORE::bless doesn't get compiled away
# We will replace $bless_override only if we are in author mode
my $bless_override;
BEGIN {
  $bless_override = sub {
    CORE::bless( $_[0], (@_ > 1) ? $_[1] : caller() );
  };
  *CORE::GLOBAL::bless = sub { goto $bless_override };
}

use strict;
use warnings;
use Test::More;

my $TB = Test::More->builder;
if ($ENV{DBICTEST_IN_PERSISTENT_ENV}) {
  # without this explicit close ->reset below warns
  close ($TB->$_) for qw/output failure_output/;

  # so done_testing can work
  $TB->reset;

  # this simulates a subtest
  $TB->_indent(' ' x 4);
}

use lib qw(t/lib);
use DBICTest::RunMode;
use DBIx::Class;
use B 'svref_2object';
BEGIN {
  plan skip_all => "Your perl version $] appears to leak like a sieve - skipping test"
    if DBIx::Class::_ENV_::PEEPEENESS;
}

use Scalar::Util qw/refaddr reftype weaken/;

# this is what holds all weakened refs to be checked for leakage
my $weak_registry = {};

# whether or to invoke IC::DT
my $has_dt;

# Skip the heavy-duty leak tracing when just doing an install
unless (DBICTest::RunMode->is_plain) {

  # have our own little stack maker - Carp infloops due to the bless override
  my $trace = sub {
    my $depth = 1;
    my (@stack, @frame);

    while (@frame = caller($depth++)) {
      push @stack, [@frame[3,1,2]];
    }

    $stack[0][0] = '';
    return join "\tinvoked as ", map { sprintf ("%s at %s line %d\n", @$_ ) } @stack;
  };

  # redefine the bless override so that we can catch each and every object created
  no warnings qw/redefine once/;
  no strict qw/refs/;

  $bless_override = sub {

    my $obj = CORE::bless(
      $_[0], (@_ > 1) ? $_[1] : do {
        my ($class, $fn, $line) = caller();
        fail ("bless() of $_[0] into $class without explicit class specification at $fn line $line")
          if $class =~ /^ (?: DBIx\:\:Class | DBICTest ) /x;
        $class;
      }
    );

    my $slot = (sprintf '%s=%s(0x%x)', # so we don't trigger stringification
      ref $obj,
      reftype $obj,
      refaddr $obj,
    );

    # weaken immediately to avoid weird side effects
    $weak_registry->{$slot} = { weakref => $obj, strace => $trace->() };
    weaken $weak_registry->{$slot}{weakref};

    return $obj;
  };

  require Try::Tiny;
  for my $func (qw/try catch finally/) {
    my $orig = \&{"Try::Tiny::$func"};
    *{"Try::Tiny::$func"} = sub (&;@) {

      my $slot = sprintf ('CODE(0x%x)', refaddr $_[0]);

      $weak_registry->{$slot} = { weakref => $_[0], strace => $trace->() };
      weaken $weak_registry->{$slot}{weakref};

      goto $orig;
    }
  }

  # Some modules are known to install singletons on-load
  # Load them and empty the registry

  # this loads the DT armada
  $has_dt = DBIx::Class::Optional::Dependencies->req_ok_for('test_dt_sqlite');

  require Errno;
  require DBI;
  require DBD::SQLite;
  require FileHandle;

  %$weak_registry = ();
}

my @compose_ns_classes;
{
  use_ok ('DBICTest');

  my $schema = DBICTest->init_schema;
  my $rs = $schema->resultset ('Artist');
  my $storage = $schema->storage;

  @compose_ns_classes = map { "DBICTest::${_}" } keys %{$schema->source_registrations};

  ok ($storage->connected, 'we are connected');

  my $row_obj = $rs->search({}, { rows => 1})->next;  # so that commits/rollbacks work
  ok ($row_obj, 'row from db');

  # txn_do to invoke more codepaths
  my ($mc_row_obj, $pager, $pager_explicit_count) = $schema->txn_do (sub {

    my $artist = $rs->create ({
      name => 'foo artist',
      cds => [{
        title => 'foo cd',
        year => 1984,
      }],
    });

    my $pg = $rs->search({}, { rows => 1})->page(2)->pager;

    my $pg_wcount = $rs->page(4)->pager->total_entries (66);

    return ($artist, $pg, $pg_wcount);
  });

  is ($pager->next_page, 3, 'There is one more page available');

  # based on 66 per 10 pages
  is ($pager_explicit_count->last_page, 7, 'Correct last page');

  # do some population (invokes some extra codepaths)
  # also exercise the guard code and the manual txn control
  {
    my $guard = $schema->txn_scope_guard;
    # populate with bindvars
    $rs->populate([{ name => 'James Bound' }]);
    $guard->commit;

    $schema->txn_begin;
    # populate mixed
    $rs->populate([{ name => 'James Rebound', rank => \ '11'  }]);
    $schema->txn_commit;

    $schema->txn_begin;
    # and without bindvars
    $rs->populate([{ name => \ '"James Unbound"' }]);
    $schema->txn_rollback;
  }

  # prefetching
  my $cds_rs = $schema->resultset('CD');
  my $cds_with_artist = $cds_rs->search({}, { prefetch => 'artist' });
  my $cds_with_tracks = $cds_rs->search({}, { prefetch => 'tracks' });
  my $cds_with_stuff = $cds_rs->search({}, { prefetch => [ 'genre', { artist => { cds => { tracks => 'cd_single' } } } ] });

  # implicit pref
  my $cds_with_impl_artist = $cds_rs->search({}, { columns => [qw/me.title artist.name/], join => 'artist' });

  # get_column
  my $getcol_rs = $cds_rs->get_column('me.cdid');
  my $pref_getcol_rs = $cds_with_stuff->get_column('me.cdid');

  # fire the column getters
  my @throwaway = $pref_getcol_rs->all;

  my $base_collection = {
    resultset => $rs,

    pref_precursor => $cds_rs,

    pref_rs_single => $cds_with_artist,
    pref_rs_multi => $cds_with_tracks,
    pref_rs_nested => $cds_with_stuff,

    pref_rs_implicit => $cds_with_impl_artist,

    pref_row_single => $cds_with_artist->next,
    pref_row_multi => $cds_with_tracks->next,
    pref_row_nested => $cds_with_stuff->next,

    # even though this does not leak Storable croaks on it :(((
    #pref_row_implicit => $cds_with_impl_artist->next,

    get_column_rs_plain => $getcol_rs,
    get_column_rs_pref => $pref_getcol_rs,

    # twice so that we make sure only one H::M object spawned
    chained_resultset => $rs->search_rs ({}, { '+columns' => [ 'foo' ] } ),
    chained_resultset2 => $rs->search_rs ({}, { '+columns' => [ 'bar' ] } ),

    row_object => $row_obj,

    result_source => $rs->result_source,

    result_source_handle => $rs->result_source->handle,

    pager_explicit_count => $pager_explicit_count,
  };

  require Storable;
  %$base_collection = (
    %$base_collection,
    refrozen => Storable::dclone( $base_collection ),
    rerefrozen => Storable::dclone( Storable::dclone( $base_collection ) ),
    pref_row_implicit => $cds_with_impl_artist->next,
    schema => $schema,
    storage => $storage,
    sql_maker => $storage->sql_maker,
    dbh => $storage->_dbh,
    fresh_pager => $rs->page(5)->pager,
    pager => $pager,
  );

  if ($has_dt) {
    my $rs = $base_collection->{icdt_rs} = $schema->resultset('Event');

    my $now = DateTime->now;
    for (1..5) {
      $base_collection->{"icdt_row_$_"} = $rs->create({
        created_on => DateTime->new(year => 2011, month => 1, day => $_, time_zone => "-0${_}00" ),
        starts_at => $now->clone->add(days => $_),
      });
    }

    # re-search
    my @dummy = $rs->all;
  }

  # dbh's are created in XS space, so pull them separately
  for ( grep { defined } map { @{$_->{ChildHandles}} } values %{ {DBI->installed_drivers()} } ) {
    $base_collection->{"DBI handle $_"} = $_;
  }

  if ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_leaks') ) {
    Test::Memory::Cycle::memory_cycle_ok ($base_collection, 'No cycles in the object collection')
  }

  for (keys %$base_collection) {
    $weak_registry->{"basic $_"} = { weakref => $base_collection->{$_} };
    weaken $weak_registry->{"basic $_"}{weakref};
  }
}

# check that "phantom-chaining" works - we never lose track of the original $schema
# and have access to the entire tree without leaking anything
{
  my $phantom;
  for (
    sub { DBICTest->init_schema },
    sub { shift->source('Artist') },
    sub { shift->resultset },
    sub { shift->result_source },
    sub { shift->schema },
    sub { shift->resultset('Artist') },
    sub { shift->find_or_create({ name => 'detachable' }) },
    sub { shift->result_source },
    sub { shift->schema },
    sub { shift->clone },
    sub { shift->resultset('Artist') },
    sub { shift->next },
    sub { shift->result_source },
    sub { shift->resultset },
    sub { shift->create({ name => 'detached' }) },
    sub { shift->update({ name => 'reattached' }) },
    sub { shift->discard_changes },
    sub { shift->delete },
    sub { shift->insert },
  ) {
    $phantom = $_->($phantom);

    my $slot = (sprintf 'phantom %s=%s(0x%x)', # so we don't trigger stringification
      ref $phantom,
      reftype $phantom,
      refaddr $phantom,
    );

    $weak_registry->{$slot} = $phantom;
    weaken $weak_registry->{$slot};
  }

  ok( $phantom->in_storage, 'Properly deleted/reinserted' );
  is( $phantom->name, 'reattached', 'Still correct name' );
}

# Naturally we have some exceptions
my $cleared;
for my $slot (keys %$weak_registry) {
  if ($slot =~ /^Test::Builder/) {
    # T::B 2.0 has result objects and other fancyness
    delete $weak_registry->{$slot};
  }
  elsif ($slot =~ /^SQL::Translator/) {
    # SQLT is a piece of shit, leaks all over
    delete $weak_registry->{$slot};
  }
  elsif ($slot =~ /^Hash::Merge/) {
    # only clear one object of a specific behavior - more would indicate trouble
    delete $weak_registry->{$slot}
      unless $cleared->{hash_merge_singleton}{$weak_registry->{$slot}{weakref}{behavior}}++;
  }
  elsif (DBIx::Class::_ENV_::INVISIBLE_DOLLAR_AT and $slot =~ /^__TxnScopeGuard__FIXUP__/) {
    delete $weak_registry->{$slot}
  }
  elsif ($slot =~ /^DateTime::TimeZone/) {
    # DT is going through a refactor it seems - let it leak zones for now
    delete $weak_registry->{$slot};
  }
}

# every result class has a result source instance as classdata
# make sure these are all present and distinct before ignoring
# (distinct means only 1 reference)
for my $rs_class (
  'DBICTest::BaseResult',
  @compose_ns_classes,
  map { DBICTest::Schema->class ($_) } DBICTest::Schema->sources
) {
  # need to store the SVref and examine it separately, to push the rsrc instance off the pad
  my $SV = svref_2object($rs_class->result_source_instance);
  is( $SV->REFCNT, 1, "Source instance of $rs_class referenced exactly once" );

  # ignore it
  delete $weak_registry->{$rs_class->result_source_instance};
}

# Schema classes also hold sources, but these are clones, since
# each source contains the schema (or schema class name in this case)
# Hence the clone so that the same source can be registered with
# multiple schemas
for my $moniker ( keys %{DBICTest::Schema->source_registrations || {}} ) {

  my $SV = svref_2object(DBICTest::Schema->source($moniker));
  is( $SV->REFCNT, 1, "Source instance registered under DBICTest::Schema as $moniker referenced exactly once" );

  delete $weak_registry->{DBICTest::Schema->source($moniker)};
}

for my $slot (sort keys %$weak_registry) {

  ok (! defined $weak_registry->{$slot}{weakref}, "No leaks of $slot") or do {
    my $diag = '';

    $diag .= Devel::FindRef::track ($weak_registry->{$slot}{weakref}, 20) . "\n"
      if ( $ENV{TEST_VERBOSE} && eval { require Devel::FindRef });

    if (my $stack = $weak_registry->{$slot}{strace}) {
      $diag .= "    Reference first seen$stack";
    }

    diag $diag if $diag;
  };
}

# we got so far without a failure - this is a good thing
# now let's try to rerun this script under a "persistent" environment
# this is ugly and dirty but we do not yet have a Test::Embedded or
# similar

my @pperl_cmd = (qw/pperl --prefork=1/, __FILE__);
my @pperl_term_cmd = @pperl_cmd;
splice @pperl_term_cmd, 1, 0, '--kill';

# scgi is smart and will auto-reap after -t amount of seconds
my @scgi_cmd = (qw/speedy -- -t5/, __FILE__);

SKIP: {
  skip 'Test already in a persistent loop', 1
    if $ENV{DBICTEST_IN_PERSISTENT_ENV};

  skip 'Persistence test disabled on regular installs', 1
    if DBICTest::RunMode->is_plain;

  skip 'Main test failed - skipping persistent env tests', 1
    unless $TB->is_passing;

  # set up -I
  require Config;
  local $ENV{PERL5LIB} = join ($Config::Config{path_sep}, @INC);

  local $ENV{DBICTEST_IN_PERSISTENT_ENV} = 1;

  # try with pperl
  SKIP: {
    skip 'PPerl persistent environment tests require PPerl', 1
      unless eval { require PPerl };

    # since PPerl is racy and sucks - just prime the "server"
    {
      local $ENV{DBICTEST_PERSISTENT_ENV_BAIL_EARLY} = 1;
      system(@pperl_cmd);
      sleep 1;

      # see if it actually runs - if not might as well bail now
      skip "Something is wrong with pperl ($!)", 1
        if system(@pperl_cmd);
    }

    for (1,2,3) {
      system(@pperl_cmd);
      ok (!$?, "Run in persistent env (PPerl pass $_): exit $?");
    }

    ok (! system (@pperl_term_cmd), 'killed pperl instance');
  }

  # try with speedy-cgi
  SKIP: {
    skip 'SPeedyCGI persistent environment tests require CGI::SpeedyCGI', 1
      unless eval { require CGI::SpeedyCGI };

    {
      local $ENV{DBICTEST_PERSISTENT_ENV_BAIL_EARLY} = 1;
      skip "Something is wrong with speedy ($!)", 1
        if system(@scgi_cmd);
      sleep 1;
    }

    for (1,2,3) {
      system(@scgi_cmd);
      ok (!$?, "Run in persistent env (SpeedyCGI pass $_): exit $?");
    }
  }
}

done_testing;

# just an extra precaution in case we blew away from the SKIP - since there are no
# PID files to go by (man does pperl really suck :(
END {
  unless ($ENV{DBICTEST_IN_PERSISTENT_ENV}) {
    close STDOUT;
    close STDERR;
    local $?; # otherwise test will inherit $? of the system()
    system (@pperl_term_cmd);
  }
}

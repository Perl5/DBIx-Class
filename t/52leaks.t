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
  # without this explicit close older TBs warn in END after a ->reset
  if ($TB->VERSION < 1.005) {
    close ($TB->$_) for (qw/output failure_output todo_output/);
  }

  # if I do not do this, I get happy sigpipes on new TB, no idea why
  # (the above close-and-forget doesn't work - new TB does *not* reopen
  # its handles automatically anymore)
  else {
    for (qw/failure_output todo_output/) {
      close $TB->$_;
      open ($TB->$_, '>&', *STDERR);
    }

    close $TB->output;
    open ($TB->output, '>&', *STDOUT);
  }

  # so done_testing can work on every persistent pass
  $TB->reset;
}

use lib qw(t/lib);
use DBICTest::RunMode;
use DBICTest::Util::LeakTracer qw/populate_weakregistry assert_empty_weakregistry/;
use DBIx::Class;
BEGIN {
  plan skip_all => "Your perl version $] appears to leak like a sieve - skipping test"
    if DBIx::Class::_ENV_::PEEPEENESS;
}

# this is what holds all weakened refs to be checked for leakage
my $weak_registry = {};

# whether or to invoke IC::DT
my $has_dt;

# Skip the heavy-duty leak tracing when just doing an install
unless (DBICTest::RunMode->is_plain) {

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

    # unicode is tricky, and now we happen to invoke it early via a
    # regex in connection()
    return $obj if (ref $obj) =~ /^utf8/;

    # Test Builder is now making a new object for every pass/fail (que bloat?)
    # and as such we can't really store any of its objects (since it will
    # re-populate the registry while checking it, ewwww!)
    return $obj if (ref $obj) =~ /^TB2::/;

    # weaken immediately to avoid weird side effects
    return populate_weakregistry ($weak_registry, $obj );
  };

  require Try::Tiny;
  for my $func (qw/try catch finally/) {
    my $orig = \&{"Try::Tiny::$func"};
    *{"Try::Tiny::$func"} = sub (&;@) {
      populate_weakregistry( $weak_registry, $_[0] );
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
  require Moo;

  %$weak_registry = ();
}

{
  use_ok ('DBICTest');

  my $schema = DBICTest->init_schema;
  my $rs = $schema->resultset ('Artist');
  my $storage = $schema->storage;

  ok ($storage->connected, 'we are connected');

  my $row_obj = $rs->search({}, { rows => 1})->next;  # so that commits/rollbacks work
  ok ($row_obj, 'row from db');

  # txn_do to invoke more codepaths
  my ($mc_row_obj, $pager, $pager_explicit_count) = $schema->txn_do (sub {

    my $artist = $schema->resultset('Artist')->create ({
      name => 'foo artist',
      cds => [{
        title => 'foo cd',
        year => 1984,
        tracks => [
          { title => 't1' },
          { title => 't2' },
        ],
        genre => { name => 'mauve' },
      }],
    });

    my $pg = $rs->search({}, { rows => 1})->page(2)->pager;

    my $pg_wcount = $rs->page(4)->pager->total_entries (66);

    return ($artist, $pg, $pg_wcount);
  });

  # more codepaths - error handling in txn_do
  {
    eval { $schema->txn_do ( sub {
      $storage->_dbh->begin_work;
      fail ('how did we get so far?!');
    } ) };

    eval { $schema->txn_do ( sub {
      $schema->txn_do ( sub {
        die "It's called EXCEPTION";
        fail ('how did we get so far?!');
      } );
      fail ('how did we get so far?!');
    } ) };
    like( $@, qr/It\'s called EXCEPTION/, 'Exception correctly propagated in nested txn_do' );
  }

  # dbh_do codepath
  my ($rs_bind_circref, $cond_rowobj) = $schema->storage->dbh_do ( sub {
    my $row = $_[0]->schema->resultset('Artist')->new({});
    my $rs = $_[0]->schema->resultset('Artist')->search({
      name => $row,  # this is deliberately bogus, see FIXME below!
    });
    return ($rs, $row);
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

    mc_row_object => $mc_row_obj,

    result_source => $rs->result_source,

    result_source_handle => $rs->result_source->handle,

    pager_explicit_count => $pager_explicit_count,

    leaky_resultset => $rs_bind_circref,
    leaky_resultset_cond => $cond_rowobj,
  };

  # this needs to fire, even if it can't find anything
  # see FIXME below
  # we run this only on smokers - trying to establish a pattern
  $rs_bind_circref->next
    if ( ($ENV{TRAVIS}||'') ne 'true' and DBICTest::RunMode->is_smoker);

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

  SKIP: {
    if ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_leaks') ) {
      my @w;
      local $SIG{__WARN__} = sub { $_[0] =~ /\QUnhandled type: REGEXP/ ? push @w, @_ : warn @_ };

      Test::Memory::Cycle::memory_cycle_ok ($base_collection, 'No cycles in the object collection');

      if ( $] > 5.011 ) {
        local $TODO = 'Silence warning due to RT56681';
        is (@w, 0, 'No Devel::Cycle emitted warnings');
      }
    }
    else {
      skip 'Circular ref test needs ' .  DBIx::Class::Optional::Dependencies->req_missing_for ('test_leaks'), 1;
    }
  }

  populate_weakregistry ($weak_registry, $base_collection->{$_}, "basic $_")
    for keys %$base_collection;
}

# check that "phantom-chaining" works - we never lose track of the original $schema
# and have access to the entire tree without leaking anything
{
  my $phantom;
  for (
    sub { DBICTest->init_schema( sqlite_use_file => 0 ) },
    sub { shift->source('Artist') },
    sub { shift->resultset },
    sub { shift->result_source },
    sub { shift->schema },
    sub { shift->resultset('Artist') },
    sub { shift->find_or_create({ name => 'detachable' }) },
    sub { shift->result_source },
    sub { shift->schema },
    sub { shift->clone },
    sub { shift->resultset('CD') },
    sub { shift->next },
    sub { shift->artist },
    sub { shift->search_related('cds') },
    sub { shift->next },
    sub { shift->search_related('artist') },
    sub { shift->result_source },
    sub { shift->resultset },
    sub { shift->create({ name => 'detached' }) },
    sub { shift->update({ name => 'reattached' }) },
    sub { shift->discard_changes },
    sub { shift->delete },
    sub { shift->insert },
  ) {
    $phantom = populate_weakregistry ( $weak_registry, scalar $_->($phantom) );
  }

  ok( $phantom->in_storage, 'Properly deleted/reinserted' );
  is( $phantom->name, 'reattached', 'Still correct name' );
}

# Naturally we have some exceptions
my $cleared;
for my $addr (keys %$weak_registry) {
  my $names = join "\n", keys %{$weak_registry->{$addr}{slot_names}};

  if ($names =~ /^Test::Builder/m) {
    # T::B 2.0 has result objects and other fancyness
    delete $weak_registry->{$addr};
  }
  elsif ($names =~ /^Method::Generate::(?:Accessor|Constructor)/m) {
    # Moo keeps globals around, this is normal
    delete $weak_registry->{$addr};
  }
  elsif ($names =~ /^SQL::Translator::Generator::DDL::SQLite/m) {
    # SQLT::Producer::SQLite keeps global generators around for quoted
    # and non-quoted DDL, allow one for each quoting style
    delete $weak_registry->{$addr}
      unless $cleared->{sqlt_ddl_sqlite}->{@{$weak_registry->{$addr}{weakref}->quote_chars}}++;
  }
  elsif ($names =~ /^Hash::Merge/m) {
    # only clear one object of a specific behavior - more would indicate trouble
    delete $weak_registry->{$addr}
      unless $cleared->{hash_merge_singleton}{$weak_registry->{$addr}{weakref}{behavior}}++;
  }
  elsif ($names =~ /^DateTime::TimeZone/m) {
    # DT is going through a refactor it seems - let it leak zones for now
    delete $weak_registry->{$addr};
  }
}

# FIXME !!!
# There is an actual strong circular reference taking place here, but because
# half of it is in XS no leaktracer sees it, and Devel::FindRef is equally
# stumped when trying to trace the origin. The problem is:
#
# $cond_object --> result_source --> schema --> storage --> $dbh --> {CachedKids}
#          ^                                                           /
#           \-------- bound value on prepared/cached STH  <-----------/
#
{
  local $TODO = 'This fails intermittently - see RT#82942';
  if ( my $r = ($weak_registry->{'basic leaky_resultset_cond'}||{})->{weakref} ) {
    ok(! defined $r, 'Self-referential RS conditions no longer leak!')
      or $r->result_source(undef);
  }
}

assert_empty_weakregistry ($weak_registry);

# we got so far without a failure - this is a good thing
# now let's try to rerun this script under a "persistent" environment
# this is ugly and dirty but we do not yet have a Test::Embedded or
# similar

# set up -I
require Config;
$ENV{PERL5LIB} = join ($Config::Config{path_sep}, @INC);
($ENV{PATH}) = $ENV{PATH} =~ /(.+)/;


my $persistence_tests = {
  PPerl => {
    cmd => [qw/pperl --prefork=1/, __FILE__],
  },
  'CGI::SpeedyCGI' => {
    cmd => [qw/speedy -- -t5/, __FILE__],
  },
};

# scgi is smart and will auto-reap after -t amount of seconds
# pperl needs an actual killer :(
$persistence_tests->{PPerl}{termcmd} = [
  $persistence_tests->{PPerl}{cmd}[0],
  '--kill',
  @{$persistence_tests->{PPerl}{cmd}}[ 1 .. $#{$persistence_tests->{PPerl}{cmd}} ],
];

SKIP: {
  skip 'Test already in a persistent loop', 1
    if $ENV{DBICTEST_IN_PERSISTENT_ENV};

  skip 'Main test failed - skipping persistent env tests', 1
    unless $TB->is_passing;

  local $ENV{DBICTEST_IN_PERSISTENT_ENV} = 1;

  require IPC::Open2;

  for my $type (keys %$persistence_tests) { SKIP: {
    unless (eval "require $type") {
      # Don't terminate what we didn't start
      delete $persistence_tests->{$type}{termcmd};
      skip "$type module not found", 1;
    }

    my @cmd = @{$persistence_tests->{$type}{cmd}};

    # since PPerl is racy and sucks - just prime the "server"
    {
      local $ENV{DBICTEST_PERSISTENT_ENV_BAIL_EARLY} = 1;
      system(@cmd);
      sleep 1;

      # see if the thing actually runs, if not - might as well bail now
      skip "Something is wrong with $type ($!)", 1
        if system(@cmd);
    }

    for (1,2,3) {
      note ("Starting run in persistent env ($type pass $_)");
      IPC::Open2::open2(my $out, undef, @cmd);
      my @out_lines;
      while (my $ln = <$out>) {
        next if $ln =~ /^\s*$/;
        push @out_lines, "   $ln";
        last if $ln =~ /^\d+\.\.\d+$/;  # this is persistence, we need to terminate reading on our end
      }
      print $_ for @out_lines;
      close $out;
      wait;
      ok (!$?, "Run in persistent env ($type pass $_): exit $?");
      ok (scalar @out_lines, "Run in persistent env ($type pass $_): got output");
    }

    ok (! system (@{$persistence_tests->{$type}{termcmd}}), "killed $type server instance")
      if $persistence_tests->{$type}{termcmd};
  }}
}

done_testing;

# just an extra precaution in case we blew away from the SKIP - since there are no
# PID files to go by (man does pperl really suck :(
END {
  unless ($ENV{DBICTEST_IN_PERSISTENT_ENV}) {
    close $_ for (*STDIN, *STDOUT, *STDERR);
    local $?; # otherwise test will inherit $? of the system()
    system (@{$persistence_tests->{PPerl}{termcmd}})
      if $persistence_tests->{PPerl}{termcmd};
  }
}

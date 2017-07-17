package #hide from pause
  DBICTest::BaseSchema;

use strict;
use warnings;
use base qw(DBICTest::Base DBIx::Class::Schema);

use Fcntl qw(:DEFAULT :seek :flock);
use IO::Handle ();
use DBIx::Class::_Util qw( emit_loud_diag scope_guard set_subname get_subname );
use DBICTest::Util::LeakTracer qw(populate_weakregistry assert_empty_weakregistry);
use DBICTest::Util qw( local_umask tmpdir await_flock dbg DEBUG_TEST_CONCURRENCY_LOCKS );
use Scalar::Util qw( refaddr weaken );
use Devel::GlobalDestruction ();
use namespace::clean;

# Unless we are running assertions there is no value in checking ourselves
# during regular tests - the CI will do it for us
#
if (
  DBIx::Class::_ENV_::ASSERT_NO_FAILING_SANITY_CHECKS
    and
  # full-blown 5.8 sanity-checking is waaaaaay too slow, even for CI
  (
    ! DBIx::Class::_ENV_::OLD_MRO
      or
    # still run a couple test with this, even on 5.8
    $ENV{DBICTEST_OLD_MRO_SANITY_CHECK_ASSERTIONS}
  )
) {

  __PACKAGE__->schema_sanity_checker('DBIx::Class::Schema::SanityChecker');

  # Repeat the check on going out of scope (will catch weird runtime tinkering)
  # Add only in case we will be using it, as it slows tests down
  eval <<'EOD' or die $@;

  sub DESTROY {
    if (
      ! Devel::GlobalDestruction::in_global_destruction()
        and
      my $checker = $_[0]->schema_sanity_checker
    ) {
      $checker->perform_schema_sanity_checks($_[0]);
    }

    # *NOT* using next::method here - it (currently) will confuse Class::C3
    # in some obscure cases ( 5.8 naturally )
    shift->SUPER::DESTROY();
  }

  1;

EOD

}
else {
  # otherwise just unset the default
  __PACKAGE__->schema_sanity_checker('');
}


if( $ENV{DBICTEST_ASSERT_NO_SPURIOUS_EXCEPTION_ACTION} ) {
  my $ea = __PACKAGE__->exception_action( sub {

    # Can not rely on $^S here at all - the exception_action
    # itself is always called in an eval so that the goto-guard
    # can work (see 7cb35852)

    my ( $fr_num, $disarmed, $throw_exception_fr_num, $eval_fr_num );
    while( ! $disarmed and my @fr = caller(++$fr_num) ) {

      $throw_exception_fr_num ||= (
        $fr[3] =~ /^DBIx::Class::(?:ResultSource|Schema|Storage|Exception)::throw(?:_exception)?$/
          and
        # there may be evals in the throwers themselves - skip those
        ( $eval_fr_num ) = ( undef )
          and
        $fr_num
      );

      # now that the above stops un-setting us, we can find the first
      # ineresting eval
      $eval_fr_num ||= (
        $fr[3] eq '(eval)'
          and
        $fr_num
      );

      $disarmed = !! (
        $fr[1] =~ / \A (?: \. [\/\\] )? x?t [\/\\] .+ \.t \z /x
          and
        (
          $fr[3] =~ /\A (?:
            Test::Exception::throws_ok
              |
            Test::Exception::dies_ok
              |
            Try::Tiny::try
              |
            \Q(eval)\E
          ) \z /x
            or
          (
            $fr[3] eq 'Test::Exception::lives_ok'
              and
            ( $::TODO or Test::Builder->new->in_todo )
          )
        )
      );
    }

    Test::Builder->new->ok(0, join "\n",
      'Unexpected &exception_action invocation',
      '',
      '  You almost certainly used eval/try instead of dbic_internal_try()',
      "  Adjust *one* of the eval-ish constructs in the callstack starting" . DBICTest::Util::stacktrace($throw_exception_fr_num||())
    ) if (
      ! $disarmed
        and
      (
        $eval_fr_num
          or
        ! $throw_exception_fr_num
      )
    );

    DBIx::Class::Exception->throw( $_[0] );
  });

  my $interesting_ns_rx = qr/^ (?: main$ | DBIx::Class:: | DBICTest:: ) /x;

  # hard-set $SIG{__DIE__} to the class-wide exception_action
  # with a little escape preceeding it
  $SIG{__DIE__} = sub {

    # without this there would be false positives everywhere :(
    die @_ if (
      # blindly rethrow if nobody is waiting for us
      ( defined $^S and ! $^S )
        or
      (caller(0))[0] !~ $interesting_ns_rx
        or
      (
        caller(0) eq 'main'
          and
        ( (caller(1))[0] || '' ) !~ $interesting_ns_rx
      )
    );

    &$ea;
  };
}

sub capture_executed_sql_bind {
  my ($self, $cref) = @_;

  $self->throw_exception("Expecting a coderef to run") unless ref $cref eq 'CODE';

  require DBICTest::SQLTracerObj;

  # hack around stupid, stupid API
  no warnings 'redefine';
  local *DBIx::Class::Storage::DBI::_format_for_trace = sub { $_[1] };
  Class::C3->reinitialize if DBIx::Class::_ENV_::OLD_MRO;

  # can not use local() due to an unknown number of storages
  # (think replicated)
  my $orig_states = { map
    { $_ => $self->storage->$_ }
    qw(debugcb debugobj debug)
  };

  my $sg = scope_guard {
    $self->storage->$_ ( $orig_states->{$_} ) for keys %$orig_states;
  };

  $self->storage->debugcb(undef);
  $self->storage->debugobj( my $tracer_obj = DBICTest::SQLTracerObj->new );
  $self->storage->debug(1);

  local $Test::Builder::Level = $Test::Builder::Level + 2;
  $cref->();

  return $tracer_obj->{sqlbinds} || [];
}

sub is_executed_querycount {
  my ($self, $cref, $exp_counts, $msg) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  $self->throw_exception("Expecting an hashref of counts or an integer representing total query count")
    unless ref $exp_counts eq 'HASH' or (defined $exp_counts and ! ref $exp_counts);

  my @got = map { $_->[0] } @{ $self->capture_executed_sql_bind($cref) };

  return Test::More::is( @got, $exp_counts, $msg )
    unless ref $exp_counts;

  my $got_counts = { map { $_ => 0 } keys %$exp_counts };
  $got_counts->{$_}++ for @got;

  return Test::More::is_deeply(
    $got_counts,
    $exp_counts,
    $msg,
  );
}

sub is_executed_sql_bind {
  my ($self, $cref, $sqlbinds, $msg) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  $self->throw_exception("Expecting an arrayref of SQL/Bind pairs") unless ref $sqlbinds eq 'ARRAY';

  my @expected = @$sqlbinds;

  my @got = map { $_->[1] } @{ $self->capture_executed_sql_bind($cref) };


  return Test::Builder->new->ok(1, $msg || "No queries executed while running $cref")
    if !@got and !@expected;

  require SQL::Abstract::Test;
  my $ret = 1;
  while (@expected or @got) {
    my $left = shift @got;
    my $right = shift @expected;

    # allow the right side to "simplify" the entire shebang
    if ($left and $right) {
      $left = [ @$left ];
      for my $i (1..$#$right) {
        if (
          ! ref $right->[$i]
            and
          ref $left->[$i] eq 'ARRAY'
            and
          @{$left->[$i]} == 2
        ) {
          $left->[$i] = $left->[$i][1]
        }
      }
    }

    $ret &= SQL::Abstract::Test::is_same_sql_bind(
      \( $left || [] ),
      \( $right || [] ),
      $msg,
    );
  }

  return $ret;
}

our $locker;
END {
  # we need the $locker to be referenced here for delayed destruction
  if ($locker->{lock_name} and ($ENV{DBICTEST_LOCK_HOLDER}||0) == $$) {
    DEBUG_TEST_CONCURRENCY_LOCKS
      and dbg "$locker->{type} LOCK RELEASED (END): $locker->{lock_name}";
  }
}

my ( $weak_registry, $assertion_arounds ) = ( {}, {} );

sub DBICTest::__RsrcRedefiner_iThreads_handler__::CLONE {
  if( DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE ) {
    %$assertion_arounds = map {
      (defined $_)
        ? ( refaddr($_) => $_ )
        : ()
    } values %$assertion_arounds;

    weaken($_) for values %$assertion_arounds;
  }
}

sub connection {
  my $self = shift->next::method(@_);

# MASSIVE FIXME
# we can't really lock based on DSN, as we do not yet have a way to tell that e.g.
# DBICTEST_MSSQL_DSN=dbi:Sybase:server=192.168.0.11:1433;database=dbtst
#  and
# DBICTEST_MSSQL_ODBC_DSN=dbi:ODBC:server=192.168.0.11;port=1433;database=dbtst;driver=FreeTDS;tds_version=8.0
# are the same server
# hence we lock everything based on sqlt_type or just globally if not available
# just pretend we are python you know? :)


  # when we get a proper DSN resolution sanitize to produce a portable lockfile name
  # this may look weird and unnecessary, but consider running tests from
  # windows over a samba share >.>
  #utf8::encode($dsn);
  #$dsn =~ s/([^A-Za-z0-9_\-\.\=])/ sprintf '~%02X', ord($1) /ge;
  #$dsn =~ s/^dbi/dbi/i;

  # provide locking for physical (non-memory) DSNs, so that tests can
  # safely run in parallel. While the harness (make -jN test) does set
  # an envvar, we can not detect when a user invokes prove -jN. Hence
  # perform the locking at all times, it shouldn't hurt.
  # the lock fh *should* inherit across forks/subprocesses
  if (
    ! $DBICTest::global_exclusive_lock
      and
    ( ! $ENV{DBICTEST_LOCK_HOLDER} or $ENV{DBICTEST_LOCK_HOLDER} == $$ )
      and
    ref($_[0]) ne 'CODE'
      and
    ($_[0]||'') !~ /^ (?i:dbi) \: SQLite (?: \: | \W ) .*? (?: dbname\= )? (?: \:memory\: | t [\/\\] var [\/\\] DBIxClass\-) /x
  ) {

    my $locktype;

    {
      # guard against infinite recursion
      local $ENV{DBICTEST_LOCK_HOLDER} = -1;

      # we need to work with a forced fresh clone so that we do not upset any state
      # of the main $schema (some tests examine it quite closely)
      local $SIG{__WARN__} = sub {};
      local $SIG{__DIE__} if $SIG{__DIE__};
      local $@;

      # this will either give us an undef $locktype or will determine things
      # properly with a default ( possibly connecting in the process )
      eval {
        my $cur_storage = $self->storage;

        $cur_storage = $cur_storage->master
          if $cur_storage->isa('DBIx::Class::Storage::DBI::Replicated');

        my $s = ref($self)->connect(@{$cur_storage->connect_info})->storage;

        $locktype = $s->sqlt_type || 'generic';

        # in case sqlt_type did connect, doesn't matter if it fails or something
        $s->disconnect;
      };
    }

    # Never hold more than one lock. This solves the "lock in order" issues
    # unrelated tests may have
    # Also if there is no connection - there is no lock to be had
    if ($locktype and (!$locker or $locker->{type} ne $locktype)) {

      # this will release whatever lock we may currently be holding
      # which is fine since the type does not match as checked above
      DEBUG_TEST_CONCURRENCY_LOCKS
        and $locker
        and dbg "$locker->{type} LOCK RELEASED (UNDEF): $locker->{lock_name}";

      undef $locker;

      my $lockpath = tmpdir . "_dbictest_$locktype.lock";

      DEBUG_TEST_CONCURRENCY_LOCKS
        and dbg "Waiting for $locktype LOCK: $lockpath...";

      my $lock_fh;
      {
        my $u = local_umask(0); # so that the file opens as 666, and any user can lock
        sysopen ($lock_fh, $lockpath, O_RDWR|O_CREAT) or die "Unable to open $lockpath: $!";
      }

      await_flock ($lock_fh, LOCK_EX) or die "Unable to lock $lockpath: $!";

      DEBUG_TEST_CONCURRENCY_LOCKS
        and dbg "Got $locktype LOCK: $lockpath";

      # see if anyone was holding a lock before us, and wait up to 5 seconds for them to terminate
      # if we do not do this we may end up trampling over some long-running END or somesuch
      seek ($lock_fh, 0, SEEK_SET) or die "seek failed $!";
      my $old_pid;
      if (
        read ($lock_fh, $old_pid, 100)
          and
        ($old_pid) = $old_pid =~ /^(\d+)$/
      ) {
        DEBUG_TEST_CONCURRENCY_LOCKS
          and dbg "Post-grab WAIT for $old_pid START: $lockpath";

        for (1..50) {
          kill (0, $old_pid) or last;
          select( undef, undef, undef, 0.1 );
        }

        DEBUG_TEST_CONCURRENCY_LOCKS
          and dbg "Post-grab WAIT for $old_pid FINISHED: $lockpath";
      }

      truncate $lock_fh, 0;
      seek ($lock_fh, 0, SEEK_SET) or die "seek failed $!";
      $lock_fh->autoflush(1);
      print $lock_fh $$;

      $ENV{DBICTEST_LOCK_HOLDER} ||= $$;

      $locker = {
        type => $locktype,
        fh => $lock_fh,
        lock_name => "$lockpath",
      };
    }
  }

  if ($INC{'Test/Builder.pm'}) {
    populate_weakregistry ( $weak_registry, $self->storage );

    my $cur_connect_call = $self->storage->on_connect_call;

    $self->storage->on_connect_call([
      (ref $cur_connect_call eq 'ARRAY'
        ? @$cur_connect_call
        : ($cur_connect_call || ())
      ),
      [sub {
        populate_weakregistry( $weak_registry, shift->_dbh )
      }],
    ]);
  }

  #
  # Check an explicit level of indirection: makes sure that folks doing
  # use `base "DBIx::Class::Core"; __PACKAGE__->add_column("foo")`
  # will see the correct error message
  #
  # In the future this all is likely to be folded into a single method in
  # some way, but that's a fight for another maint
  #
  if( DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE ) {

    for my $class_of_interest (
      'DBIx::Class::Row',
      map { $self->class($_) } ($self->sources)
    ) {

      my $orig_rsrc = $class_of_interest->can('result_source')
        or die "How did we get here?!";

      unless ( $assertion_arounds->{refaddr $orig_rsrc} ) {

        my ($origin) = get_subname($orig_rsrc);

        no warnings 'redefine';
        no strict 'refs';

        *{"${origin}::result_source"} = my $replacement = set_subname "${origin}::result_source" => sub {


          @_ > 1
            and
          (CORE::caller(0))[1] !~ / (?: ^ | [\/\\] ) x?t [\/\\] .+? \.t $ /x
            and
          emit_loud_diag(
            msg => 'Incorrect indirect call of result_source() as setter must be changed to result_source_instance()',
            confess => 1,
          );


          grep {
            ! (CORE::caller($_))[7]
              and
            ( (CORE::caller($_))[3] || '' ) eq '(eval)'
              and
            ( (CORE::caller($_))[1] || '' ) !~ / (?: ^ | [\/\\] ) x?t [\/\\] .+? \.t $ /x
          } (0..2)
            and
          # these evals are legit
          ( (CORE::caller(4))[3] || '' ) !~ /^ (?:
            DBIx::Class::Schema::_ns_get_rsrc_instance
              |
            DBIx::Class::Relationship::BelongsTo::belongs_to
              |
            DBIx::Class::Relationship::HasOne::_has_one
              |
            Class::C3::Componentised::.+
          ) $/x
            and
          emit_loud_diag(
            # not much else we can do (aside from exit(1) which is too obnoxious)
            msg => 'Incorrect call of result_source() in an eval',
            emit_dups => 1,
          );


          &$orig_rsrc;
        };

        weaken( $assertion_arounds->{refaddr $replacement} = $replacement );

        attributes->import(
          $origin,
          $replacement,
          attributes::get($orig_rsrc)
        );
      }


      # no rsrc_instance to mangle
      next if $class_of_interest eq 'DBIx::Class::Row';


      my $orig_rsrc_instance = $class_of_interest->can('result_source_instance')
        or die "How did we get here?!";

      # Do the around() per definition-site as result_source_instance is a CAG inherited cref
      unless ( $assertion_arounds->{refaddr $orig_rsrc_instance} ) {

        my ($origin) = get_subname($orig_rsrc_instance);

        no warnings 'redefine';
        no strict 'refs';

        *{"${origin}::result_source_instance"} = my $replacement = set_subname "${origin}::result_source_instance" => sub {


          @_ == 1
            and
          # special cased as we do not care whether there is a source
          ( (CORE::caller(4))[3] || '' ) ne 'DBIx::Class::Schema::_register_source'
            and
          # special case because I am paranoid
          ( (CORE::caller(4))[3] || '' ) ne 'DBIx::Class::Row::throw_exception'
            and
          ( (CORE::caller(1))[3] || '' ) !~ / ^ DBIx::Class:: (?:
            Row::result_source
              |
            Row::throw_exception
              |
            ResultSourceProxy::Table:: (?: _init_result_source_instance | table )
              |
            ResultSourceHandle::STORABLE_thaw
          ) $ /x
            and
          (CORE::caller(0))[1] !~ / (?: ^ | [\/\\] ) x?t [\/\\] .+? \.t $ /x
            and
          emit_loud_diag(
            msg => 'Incorrect direct call of result_source_instance() as getter must be changed to result_source()',
            confess => 1
          );


          grep {
            ! (CORE::caller($_))[7]
              and
            ( (CORE::caller($_))[3] || '' ) eq '(eval)'
              and
            ( (CORE::caller($_))[1] || '' ) !~ / (?: ^ | [\/\\] ) x?t [\/\\] .+? \.t $ /x
          } (0..2)
            and
          # special cased as we do not care whether there is a source
          ( (CORE::caller(4))[3] || '' ) ne 'DBIx::Class::Schema::_register_source'
            and
          # special case because I am paranoid
          ( (CORE::caller(4))[3] || '' ) ne 'DBIx::Class::Row::throw_exception'
            and
          # special case for Storable, which in turn calls from an eval
          ( (CORE::caller(1))[3] || '' ) ne 'DBIx::Class::ResultSourceHandle::STORABLE_thaw'
            and
          emit_loud_diag(
            # not much else we can do (aside from exit(1) which is too obnoxious)
            msg => 'Incorrect call of result_source_instance() in an eval',
            skip_frames => 1,
            emit_dups => 1,
          );

          &$orig_rsrc_instance;
        };

        weaken( $assertion_arounds->{refaddr $replacement} = $replacement );

        attributes->import(
          $origin,
          $replacement,
          attributes::get($orig_rsrc_instance)
        );
      }
    }

    Class::C3::initialize if DBIx::Class::_ENV_::OLD_MRO;
  }
  #
  # END Check an explicit level of indirection

  return $self;
}

sub clone {
  my $self = shift->next::method(@_);
  populate_weakregistry ( $weak_registry, $self )
    if $INC{'Test/Builder.pm'};
  $self;
}

END {
  # Make sure we run after any cleanup in other END blocks
  push @{ B::end_av()->object_2svref }, sub {
    assert_empty_weakregistry($weak_registry, 'quiet');
  };
}

1;

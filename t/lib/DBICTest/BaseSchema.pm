package #hide from pause
  DBICTest::BaseSchema;

use strict;
use warnings;
use base qw(DBICTest::Base DBIx::Class::Schema);

use Fcntl qw(:DEFAULT :seek :flock);
use Time::HiRes 'sleep';
use DBICTest::Util::LeakTracer qw(populate_weakregistry assert_empty_weakregistry);
use DBICTest::Util 'local_umask';
use namespace::clean;

sub capture_executed_sql_bind {
  my ($self, $cref) = @_;

  $self->throw_exception("Expecting a coderef to run") unless ref $cref eq 'CODE';

  require DBICTest::SQLTracerObj;

  # hack around stupid, stupid API
  no warnings 'redefine';
  local *DBIx::Class::Storage::DBI::_format_for_trace = sub { $_[1] };
  Class::C3->reinitialize if DBIx::Class::_ENV_::OLD_MRO;


  local $self->storage->{debugcb};
  local $self->storage->{debugobj} = my $tracer_obj = DBICTest::SQLTracerObj->new;
  local $self->storage->{debug} = 1;

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
    #warn "$$ $0 $locker->{type} LOCK RELEASED";
  }
}

my $weak_registry = {};

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
  #
  # File locking is hard. Really hard. By far the best lock implementation
  # I've seen is part of the guts of File::Temp. However it is sadly not
  # reusable. Since I am not aware of folks doing NFS parallel testing,
  # nor are we known to work on VMS, I am just going to punt this and
  # use the portable-ish flock() provided by perl itself. If this does
  # not work for you - patches more than welcome.
  if (
    ! $DBICTest::global_exclusive_lock
      and
    ( ! $ENV{DBICTEST_LOCK_HOLDER} or $ENV{DBICTEST_LOCK_HOLDER} == $$ )
      and
    ref($_[0]) ne 'CODE'
      and
    ($_[0]||'') !~ /^ (?i:dbi) \: SQLite \: (?: dbname\= )? (?: \:memory\: | t [\/\\] var [\/\\] DBIxClass\-) /x
  ) {

    my $locktype = do {
      # guard against infinite recursion
      local $ENV{DBICTEST_LOCK_HOLDER} = -1;

      # we need to connect a forced fresh clone so that we do not upset any state
      # of the main $schema (some tests examine it quite closely)
      local $SIG{__WARN__} = sub {};
      local $@;
      my $storage = eval {
        my $st = ref($self)->connect(@{$self->storage->connect_info})->storage;
        $st->ensure_connected;  # do connect here, to catch a possible throw
        $st;
      };
      $storage
        ? do {
          my $t = $storage->sqlt_type || 'generic';
          eval { $storage->disconnect };
          $t;
        }
        : undef
      ;
    };

    # Never hold more than one lock. This solves the "lock in order" issues
    # unrelated tests may have
    # Also if there is no connection - there is no lock to be had
    if ($locktype and (!$locker or $locker->{type} ne $locktype)) {

      # this will release whatever lock we may currently be holding
      # which is fine since the type does not match as checked above
      undef $locker;

      my $lockpath = DBICTest::RunMode->tmpdir->file("_dbictest_$locktype.lock");

      #warn "$$ $0 $locktype GRABBING LOCK";
      my $lock_fh;
      {
        my $u = local_umask(0); # so that the file opens as 666, and any user can lock
        sysopen ($lock_fh, $lockpath, O_RDWR|O_CREAT) or die "Unable to open $lockpath: $!";
      }
      flock ($lock_fh, LOCK_EX) or die "Unable to lock $lockpath: $!";
      #warn "$$ $0 $locktype LOCK GRABBED";

      # see if anyone was holding a lock before us, and wait up to 5 seconds for them to terminate
      # if we do not do this we may end up trampling over some long-running END or somesuch
      seek ($lock_fh, 0, SEEK_SET) or die "seek failed $!";
      my $old_pid;
      if (
        read ($lock_fh, $old_pid, 100)
          and
        ($old_pid) = $old_pid =~ /^(\d+)$/
      ) {
        for (1..50) {
          kill (0, $old_pid) or last;
          sleep 0.1;
        }
      }
      #warn "$$ $0 $locktype POST GRAB WAIT";

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
  require B;
  push @{ B::end_av()->object_2svref }, sub {
    assert_empty_weakregistry($weak_registry, 'quiet');
  };
}

1;

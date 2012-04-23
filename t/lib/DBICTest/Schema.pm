package # hide from PAUSE
    DBICTest::Schema;

use strict;
use warnings;
no warnings 'qw';

use base 'DBICTest::BaseSchema';

use Fcntl qw/:DEFAULT :seek :flock/;
use Time::HiRes 'sleep';
use DBICTest::RunMode;
use DBICTest::Util qw/populate_weakregistry assert_empty_weakregistry local_umask/;
use namespace::clean;

__PACKAGE__->mk_group_accessors(simple => 'custom_attr');

__PACKAGE__->load_classes(qw/
  Artist
  SequenceTest
  BindType
  Employee
  CD
  Genre
  Bookmark
  Link
  #dummy
  Track
  Tag
  Year2000CDs
  Year1999CDs
  CustomSql
  Money
  TimestampPrimaryKey
  /,
  { 'DBICTest::Schema' => [qw/
    LinerNotes
    Artwork
    Artwork_to_Artist
    Image
    Lyrics
    LyricVersion
    OneKey
    #dummy
    TwoKeys
    Serialized
  /]},
  (
    'FourKeys',
    'FourKeys_to_TwoKeys',
    '#dummy',
    'SelfRef',
    'ArtistUndirectedMap',
    'ArtistSourceName',
    'ArtistSubclass',
    'Producer',
    'CD_to_Producer',
    'Dummy',    # this is a real result class we remove in the hook below
  ),
  qw/SelfRefAlias TreeLike TwoKeyTreeLike Event EventTZ NoPrimaryKey/,
  qw/Collection CollectionObject TypedObject Owners BooksInLibrary/,
  qw/ForceForeign Encoded/,
);

sub sqlt_deploy_hook {
  my ($self, $sqlt_schema) = @_;

  $sqlt_schema->drop_table('dummy');
}


our $locker;
END {
  # we need the $locker to be referenced here for delayed destruction
  if ($locker->{lock_name} and ($ENV{DBICTEST_LOCK_HOLDER}||0) == $$) {
    #warn "$$ $0 $locktype LOCK RELEASED";
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

      warn "$$ $0 $locktype" if (
        ($locktype eq 'generic' or $locktype eq 'SQLite')
          and
        DBICTest::RunMode->is_author
      );

      my $lockpath = DBICTest::RunMode->tmpdir->file(".dbictest_$locktype.lock");

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
  assert_empty_weakregistry($weak_registry, 'quiet');
}

1;

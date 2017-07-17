package # hide from PAUSE
    DBICTest;

# load early so that `perl -It/lib -MDBICTest` keeps  working
use ANFANG;

use strict;
use warnings;


# this noop trick initializes the STDOUT, so that the TAP::Harness
# issued IO::Select->can_read calls (which are blocking wtf wtf wtf)
# keep spinning and scheduling jobs
# This results in an overall much smoother job-queue drainage, since
# the Harness blocks less
# (ideally this needs to be addressed in T::H, but a quick patchjob
# broke everything so tabling it for now)
BEGIN {
  # FIXME - there probably is some way to determine a harness run (T::H or
  # prove) but I do not know it offhand, especially on older environments
  # Go with the safer option
  if ($INC{'Test/Builder.pm'}) {
    select( ( select(\*STDOUT), $|=1 )[0] );
    print STDOUT "#\n";
  }
}


use DBICTest::Util qw(
  local_umask slurp_bytes tmpdir await_flock
  dbg DEBUG_TEST_CONCURRENCY_LOCKS PEEPEENESS
);
use DBICTest::Util::LeakTracer qw/populate_weakregistry assert_empty_weakregistry/;

# The actual ASSERT logic is in BaseSchema for pesky load-order reasons
# Hence run this through once, *before* DBICTest::Schema and friends load
BEGIN {
  if (
    DBIx::Class::_ENV_::ASSERT_NO_ERRONEOUS_METAINSTANCE_USE
      or
    DBIx::Class::_ENV_::ASSERT_NO_INTERNAL_INDIRECT_CALLS
  ) {
    require DBIx::Class::Row;
    require DBICTest::BaseSchema;
    DBICTest::BaseSchema->connect( sub {} );
  }
}

use DBICTest::Schema;
use DBIx::Class::_Util qw( detected_reinvoked_destructor scope_guard modver_gt_or_eq );
use Carp;
use Fcntl qw/:DEFAULT :flock/;
use Config;

=head1 NAME

DBICTest - Library to be used by DBIx::Class test scripts

=head1 SYNOPSIS

  BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

  use warnings;
  use strict;
  use Test::More;
  use DBICTest;

  my $schema = DBICTest->init_schema();

=head1 DESCRIPTION

This module provides the basic utilities to write tests against
DBIx::Class.

=head1 EXPORTS

The module does not export anything by default, nor provides individual
function exports in the conventional sense. Instead the following tags are
recognized:

=head2 :DiffSQL

Same as C<use SQL::Abstract::Test
qw(L<is_same_sql_bind|SQL::Abstract::Test/is_same_sql_bind>
L<is_same_sql|SQL::Abstract::Test/is_same_sql>
L<is_same_bind|SQL::Abstract::Test/is_same_bind>)>

=head2 :GlobalLock

Some tests are very time sensitive and need to run on their own, without
being disturbed by anything else grabbing CPU or disk IO. Hence why everything
using C<DBICTest> grabs a shared lock, and the few tests that request a
C<:GlobalLock> will ask for an exclusive one and block until they can get it.

=head1 METHODS

=head2 init_schema

  my $schema = DBICTest->init_schema(
    no_deploy=>1,
    no_populate=>1,
    storage_type=>'::DBI::Replicated',
    storage_type_args=>{
      balancer_type=>'DBIx::Class::Storage::DBI::Replicated::Balancer::Random'
    },
  );

This method removes the test SQLite database in t/var/DBIxClass.db
and then creates a new, empty database.

This method will call L<deploy_schema()|/deploy_schema> by default, unless the
C<no_deploy> flag is set.

Also, by default, this method will call L<populate_schema()|/populate_schema>
by default, unless the C<no_deploy> or C<no_populate> flags are set.

=cut

# see L</:GlobalLock>
our ($global_lock_fh, $global_exclusive_lock);
sub import {
    my $self = shift;

    my $lockpath = tmpdir . '_dbictest_global.lock';

    {
      my $u = local_umask(0); # so that the file opens as 666, and any user can lock
      sysopen ($global_lock_fh, $lockpath, O_RDWR|O_CREAT)
        or die "Unable to open $lockpath: $!";
    }

    for my $exp (@_) {
        if ($exp eq ':GlobalLock') {
            DEBUG_TEST_CONCURRENCY_LOCKS > 1
              and dbg "Waiting for EXCLUSIVE global lock...";

            await_flock ($global_lock_fh, LOCK_EX) or die "Unable to lock $lockpath: $!";

            DEBUG_TEST_CONCURRENCY_LOCKS > 1
              and dbg "Got EXCLUSIVE global lock";

            $global_exclusive_lock = 1;
        }
        elsif ($exp eq ':DiffSQL') {
            require SQL::Abstract::Test;
            my $into = caller(0);
            for (qw(is_same_sql_bind is_same_sql is_same_bind)) {
              no strict 'refs';
              *{"${into}::$_"} = \&{"SQL::Abstract::Test::$_"};
            }
        }
        else {
            croak "Unknown export $exp requested from $self";
        }
    }

    unless ($global_exclusive_lock) {
        DEBUG_TEST_CONCURRENCY_LOCKS > 1
          and dbg "Waiting for SHARED global lock...";

        await_flock ($global_lock_fh, LOCK_SH) or die "Unable to lock $lockpath: $!";

        DEBUG_TEST_CONCURRENCY_LOCKS > 1
          and dbg "Got SHARED global lock";
    }
}

END {
  # referencing here delays destruction even more
  if ($global_lock_fh) {
    DEBUG_TEST_CONCURRENCY_LOCKS > 1
      and dbg "Release @{[ $global_exclusive_lock ? 'EXCLUSIVE' : 'SHARED' ]} global lock (END)";
    1;
  }

  _cleanup_dbfile();
}

sub _sqlite_dbfilename {
  my $holder = $ENV{DBICTEST_LOCK_HOLDER} || $$;
  $holder = $$ if $holder == -1;

  return "t/var/DBIxClass-$holder.db";
}

$SIG{INT} = sub { _cleanup_dbfile(); exit 1 };

my $need_global_cleanup;
sub _cleanup_dbfile {
    # cleanup if this is us
    if (
      ! $ENV{DBICTEST_LOCK_HOLDER}
        or
      $ENV{DBICTEST_LOCK_HOLDER} == -1
        or
      $ENV{DBICTEST_LOCK_HOLDER} == $$
    ) {
        if ($need_global_cleanup and my $dbh = DBICTest->schema->storage->_dbh) {
          $dbh->disconnect;
        }

        my $db_file = _sqlite_dbfilename();
        unlink $_ for ($db_file, "${db_file}-journal");
    }
}

sub has_custom_dsn {
    return $ENV{"DBICTEST_DSN"} ? 1:0;
}

sub _sqlite_dbname {
    my $self = shift;
    my %args = @_;
    return $self->_sqlite_dbfilename if (
      defined $args{sqlite_use_file} ? $args{sqlite_use_file} : $ENV{'DBICTEST_SQLITE_USE_FILE'}
    );
    return ":memory:";
}

sub _database {
    my $self = shift;
    my %args = @_;

    if ($ENV{DBICTEST_DSN}) {
      return (
        (map { $ENV{"DBICTEST_${_}"} || '' } qw/DSN DBUSER DBPASS/),
        { AutoCommit => 1, %args },
      );
    }
    my $db_file = $self->_sqlite_dbname(%args);

    for ($db_file, "${db_file}-journal") {
      next unless -e $_;
      unlink ($_) or carp (
        "Unable to unlink existing test database file $_ ($!), creation of fresh database / further tests may fail!"
      );
    }

    return ("dbi:SQLite:${db_file}", '', '', {
      AutoCommit => 1,

      # this is executed on every connect, and thus installs a disconnect/DESTROY
      # guard for every new $dbh
      on_connect_do => sub {

        my $storage = shift;
        my $dbh = $storage->_get_dbh;

        # no fsync on commit
        $dbh->do ('PRAGMA synchronous = OFF');

        if (
          $ENV{DBICTEST_SQLITE_REVERSE_DEFAULT_ORDER}
            and
          # the pragma does not work correctly before libsqlite 3.7.9
          $storage->_server_info->{normalized_dbms_version} >= 3.007009
        ) {
          $dbh->do ('PRAGMA reverse_unordered_selects = ON');
        }

        # set a *DBI* disconnect callback, to make sure the physical SQLite
        # file is still there (i.e. the test does not attempt to delete
        # an open database, which fails on Win32)
        if (! $storage->{master} and my $guard_cb = __mk_disconnect_guard($db_file)) {
          $dbh->{Callbacks} = {
            connect => sub { $guard_cb->('connect') },
            disconnect => sub { $guard_cb->('disconnect') },
            DESTROY => sub { &detected_reinvoked_destructor; $guard_cb->('DESTROY') },
          };
        }
      },
      %args,
    });
}

sub __mk_disconnect_guard {

  my $db_file = shift;

  return if (
    # this perl leaks handles, delaying DESTROY, can't work right
    PEEPEENESS
      or
    ! -f $db_file
  );


  my $orig_inode = (stat($db_file))[1]
    or return;

  my $clan_connect_caller = '*UNKNOWN*';
  my $i;
  while ( my ($pack, $file, $line) = CORE::caller(++$i) ) {
    next if $file eq __FILE__;
    next if $pack =~ /^DBIx::Class|^Try::Tiny/;
    $clan_connect_caller = "$file line $line";
  }

  my $failed_once = 0;
  my $connected = 1;

  return sub {
    return if $failed_once;

    my $event = shift;
    if ($event eq 'connect') {
      # this is necessary in case we are disconnected and connected again, all within the same $dbh object
      $connected = 1;
      return;
    }
    elsif ($event eq 'disconnect') {
      return unless $connected; # we already disconnected earlier
      $connected = 0;
    }
    elsif ($event eq 'DESTROY' and ! $connected ) {
      return;
    }

    my $fail_reason;
    if (! -e $db_file) {
      $fail_reason = 'is missing';
    }
    else {
      my $cur_inode = (stat($db_file))[1];

      if ($orig_inode != $cur_inode) {
        my @inodes = ($orig_inode, $cur_inode);
        # unless this is a fixed perl (P5RT#84590) pack/unpack before display
        # to match the unsigned longs returned by `stat`
        @inodes = map { unpack ('L', pack ('l', $_) ) } @inodes
          unless $Config{st_ino_size};

        $fail_reason = sprintf
          'was recreated (initially inode %s, now %s)',
          @inodes
        ;
      }
    }

    if ($fail_reason) {
      $failed_once++;

      require Test::Builder;
      my $t = Test::Builder->new;
      local $Test::Builder::Level = $Test::Builder::Level + 3;
      $t->ok (0,
        "$db_file originally created at $clan_connect_caller $fail_reason before $event "
      . 'of DBI handle - a strong indicator that the database file was tampered with while '
      . 'still being open. This action would fail massively if running under Win32, hence '
      . 'we make sure it fails on any OS :)'
      );
    }

    return; # this empty return is a DBI requirement
  };
}

my $weak_registry = {};

sub init_schema {
    my $self = shift;
    my %args = @_;

    my $schema;

    if (
      $ENV{DBICTEST_VIA_REPLICATED} &&= (
        !$args{storage_type}
          &&
        ( ! defined $args{sqlite_use_file} or $args{sqlite_use_file} )
      )
    ) {
      $args{storage_type} = ['::DBI::Replicated', { balancer_type => '::Random' }];
      $args{sqlite_use_file} = 1;
    }

    my @dsn = $self->_database(%args);

    if ($args{compose_connection}) {
      $need_global_cleanup = 1;
      $schema = DBICTest::Schema->compose_connection(
                  'DBICTest', @dsn
                );
    } else {
      $schema = DBICTest::Schema->compose_namespace('DBICTest');
    }

    if( $args{storage_type}) {
      $schema->storage_type($args{storage_type});
    }

    if ( !$args{no_connect} ) {
      $schema->connection(@dsn);

      if( $ENV{DBICTEST_VIA_REPLICATED} ) {

        # add explicit ReadOnly=1 if we can support it
        $dsn[0] =~ /^dbi:SQLite:/i
          and
        require DBD::SQLite
          and
        modver_gt_or_eq('DBD::SQLite', '1.49_05')
          and
        $dsn[0] =~ s/^dbi:SQLite:/dbi:SQLite(ReadOnly=1):/i;

        $schema->storage->connect_replicants(\@dsn);
      }
    }

    if ( !$args{no_deploy} ) {
        __PACKAGE__->deploy_schema( $schema, $args{deploy_args} );
        __PACKAGE__->populate_schema( $schema )
         if( !$args{no_populate} );
    }

    populate_weakregistry ( $weak_registry, $schema->storage )
      if $INC{'Test/Builder.pm'} and $schema->storage;

    return $schema;
}

END {
  # Make sure we run after any cleanup in other END blocks
  push @{ B::end_av()->object_2svref }, sub {
    assert_empty_weakregistry($weak_registry, 'quiet');
  };
}

=head2 deploy_schema

  DBICTest->deploy_schema( $schema );

This method does one of two things to the schema.  It can either call
the experimental $schema->deploy() if the DBICTEST_SQLT_DEPLOY environment
variable is set, otherwise the default is to read in the t/lib/sqlite.sql
file and execute the SQL within. Either way you end up with a fresh set
of tables for testing.

=cut

sub deploy_schema {
    my $self = shift;
    my $schema = shift;
    my $args = shift || {};

    my $guard;
    if ( ($ENV{TRAVIS}||'') eq 'true' and my $old_dbg = $schema->storage->debug ) {
      $guard = scope_guard { $schema->storage->debug($old_dbg) };
      $schema->storage->debug(0);
    }

    if ($ENV{"DBICTEST_SQLT_DEPLOY"}) {
        $schema->deploy($args);
    } else {
        my $sql = slurp_bytes( 't/lib/sqlite.sql' );
        for my $chunk ( split (/;\s*\n+/, $sql) ) {
          if ( $chunk =~ / ^ (?! --\s* ) \S /xm ) {  # there is some real sql in the chunk - a non-space at the start of the string which is not a comment
            $schema->storage->dbh_do(sub { $_[1]->do($chunk) }) or print "Error on SQL: $chunk\n";
          }
        }
    }
    return;
}

=head2 populate_schema

  DBICTest->populate_schema( $schema );

After you deploy your schema you can use this method to populate
the tables with test data.

=cut

sub populate_schema {
    my $self = shift;
    my $schema = shift;

    my $guard;
    if ( ($ENV{TRAVIS}||'') eq 'true' and my $old_dbg = $schema->storage->debug ) {
      $guard = scope_guard { $schema->storage->debug($old_dbg) };
      $schema->storage->debug(0);
    }

    $schema->populate('Genre', [
      [qw/genreid name/],
      [qw/1       emo  /],
    ]);

    $schema->populate('Artist', [
        [ qw/artistid name/ ],
        [ 1, 'Caterwauler McCrae' ],
        [ 2, 'Random Boy Band' ],
        [ 3, 'We Are Goth' ],
    ]);

    $schema->populate('CD', [
        [ qw/cdid artist title year genreid/ ],
        [ 1, 1, "Spoonful of bees", 1999, 1 ],
        [ 2, 1, "Forkful of bees", 2001 ],
        [ 3, 1, "Caterwaulin' Blues", 1997 ],
        [ 4, 2, "Generic Manufactured Singles", 2001 ],
        [ 5, 3, "Come Be Depressed With Us", 1998 ],
    ]);

    $schema->populate('LinerNotes', [
        [ qw/liner_id notes/ ],
        [ 2, "Buy Whiskey!" ],
        [ 4, "Buy Merch!" ],
        [ 5, "Kill Yourself!" ],
    ]);

    $schema->populate('Tag', [
        [ qw/tagid cd tag/ ],
        [ 1, 1, "Blue" ],
        [ 2, 2, "Blue" ],
        [ 3, 3, "Blue" ],
        [ 4, 5, "Blue" ],
        [ 5, 2, "Cheesy" ],
        [ 6, 4, "Cheesy" ],
        [ 7, 5, "Cheesy" ],
        [ 8, 2, "Shiny" ],
        [ 9, 4, "Shiny" ],
    ]);

    $schema->populate('TwoKeys', [
        [ qw/artist cd/ ],
        [ 1, 1 ],
        [ 1, 2 ],
        [ 2, 2 ],
    ]);

    $schema->populate('FourKeys', [
        [ qw/foo bar hello goodbye sensors/ ],
        [ 1, 2, 3, 4, 'online' ],
        [ 5, 4, 3, 6, 'offline' ],
    ]);

    $schema->populate('OneKey', [
        [ qw/id artist cd/ ],
        [ 1, 1, 1 ],
        [ 2, 1, 2 ],
        [ 3, 2, 2 ],
    ]);

    $schema->populate('SelfRef', [
        [ qw/id name/ ],
        [ 1, 'First' ],
        [ 2, 'Second' ],
    ]);

    $schema->populate('SelfRefAlias', [
        [ qw/self_ref alias/ ],
        [ 1, 2 ]
    ]);

    $schema->populate('ArtistUndirectedMap', [
        [ qw/id1 id2/ ],
        [ 1, 2 ]
    ]);

    $schema->populate('Producer', [
        [ qw/producerid name/ ],
        [ 1, 'Matt S Trout' ],
        [ 2, 'Bob The Builder' ],
        [ 3, 'Fred The Phenotype' ],
    ]);

    $schema->populate('CD_to_Producer', [
        [ qw/cd producer/ ],
        [ 1, 1 ],
        [ 1, 2 ],
        [ 1, 3 ],
    ]);

    $schema->populate('TreeLike', [
        [ qw/id parent name/ ],
        [ 1, undef, 'root' ],
        [ 2, 1, 'foo'  ],
        [ 3, 2, 'bar'  ],
        [ 6, 2, 'blop' ],
        [ 4, 3, 'baz'  ],
        [ 5, 4, 'quux' ],
        [ 7, 3, 'fong'  ],
    ]);

    $schema->populate('Track', [
        [ qw/trackid cd  position title/ ],
        [ 4, 2, 1, "Stung with Success"],
        [ 5, 2, 2, "Stripy"],
        [ 6, 2, 3, "Sticky Honey"],
        [ 7, 3, 1, "Yowlin"],
        [ 8, 3, 2, "Howlin"],
        [ 9, 3, 3, "Fowlin"],
        [ 10, 4, 1, "Boring Name"],
        [ 11, 4, 2, "Boring Song"],
        [ 12, 4, 3, "No More Ideas"],
        [ 13, 5, 1, "Sad"],
        [ 14, 5, 2, "Under The Weather"],
        [ 15, 5, 3, "Suicidal"],
        [ 16, 1, 1, "The Bees Knees"],
        [ 17, 1, 2, "Apiary"],
        [ 18, 1, 3, "Beehind You"],
    ]);

    $schema->populate('Event', [
        [ qw/id starts_at created_on varchar_date varchar_datetime skip_inflation/ ],
        [ 1, '2006-04-25 22:24:33', '2006-06-22 21:00:05', '2006-07-23', '2006-05-22 19:05:07', '2006-04-21 18:04:06'],
    ]);

    $schema->populate('Link', [
        [ qw/id url title/ ],
        [ 1, '', 'aaa' ]
    ]);

    $schema->populate('Bookmark', [
        [ qw/id link/ ],
        [ 1, 1 ]
    ]);

    $schema->populate('Collection', [
        [ qw/collectionid name/ ],
        [ 1, "Tools" ],
        [ 2, "Body Parts" ],
    ]);

    $schema->populate('TypedObject', [
        [ qw/objectid type value/ ],
        [ 1, "pointy", "Awl" ],
        [ 2, "round", "Bearing" ],
        [ 3, "pointy", "Knife" ],
        [ 4, "pointy", "Tooth" ],
        [ 5, "round", "Head" ],
    ]);
    $schema->populate('CollectionObject', [
        [ qw/collection object/ ],
        [ 1, 1 ],
        [ 1, 2 ],
        [ 1, 3 ],
        [ 2, 4 ],
        [ 2, 5 ],
    ]);

    $schema->populate('Owners', [
        [ qw/id name/ ],
        [ 1, "Newton" ],
        [ 2, "Waltham" ],
    ]);

    $schema->populate('BooksInLibrary', [
        [ qw/id owner title source price/ ],
        [ 1, 1, "Programming Perl", "Library", 23 ],
        [ 2, 1, "Dynamical Systems", "Library",  37 ],
        [ 3, 2, "Best Recipe Cookbook", "Library", 65 ],
    ]);
}

1;

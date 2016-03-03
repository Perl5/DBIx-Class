BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use warnings;
use strict;

use Config;
BEGIN {
  my $skipall;

  # FIXME: this discrepancy is crazy, need to investigate
  my $mem_needed = ($Config{ptrsize} == 4)
    ? 200
    : 750
  ;

  if( ! $Config{useithreads} ) {
    $skipall = 'your perl does not support ithreads';
  }
  elsif( "$]" < 5.008005 ) {
    $skipall = 'DBIC does not actively support threads before perl 5.8.5';
  }
  elsif( $INC{'Devel/Cover.pm'} ) {
    $skipall = 'Devel::Cover does not work with ithreads yet';
  }
  elsif(
    ! $ENV{DBICTEST_RUN_ALL_TESTS}
      and
    require DBICTest::RunMode
      and
    ! DBICTest::RunMode->is_smoker
  ) {
    $skipall = "Test is too expensive (may use up to ${mem_needed}MB of memory), skipping on non-smoker";
  }
  else {
    require threads;
    threads->import();

    require DBICTest;
    # without this the can_alloc may very well shoot half of the CI down
    DBICTest->import(':GlobalLock');

    unless ( DBICTest::Util::can_alloc_MB($mem_needed) ) {
      $skipall = "Your system does not have the necessary amount of memory (${mem_needed}MB) for this ridiculous test";
    }
  }

  if( $skipall ) {
    print "1..0 # SKIP $skipall\n";
    exit 0;
  }
}

use Test::More;
use Errno ();
use DBIx::Class::_Util 'sigwarn_silencer';
use Time::HiRes qw(time sleep);

# README: If you set the env var to a number greater than 5,
#   we will use that many children
my $num_children = $ENV{DBICTEST_THREAD_STRESS} || 1;
if($num_children !~ /^[0-9]+$/ || $num_children < 5) {
   $num_children = 5;
}

my $schema = DBICTest->init_schema(no_deploy => 1);
isa_ok ($schema, 'DBICTest::Schema');

# sleep until this spot so everything starts simultaneously
# add "until turn of second" for prettier display
my $t = int( time() ) + 4;

my @threads;
SKIP: {

  local $SIG{__WARN__} = sigwarn_silencer( qr/Thread creation failed/i );

  for (1.. $num_children) {
    push @threads, threads->create(sub {
      my $tid = threads->tid;

      sleep ($t - time);
      note ("Thread $tid starting work at " . time() );

      my $rsrc = $schema->source('Artist');
      undef $schema;
      isa_ok ($rsrc->schema, 'DBICTest::Schema');
      my $s2 = $rsrc->schema->clone;

      sleep (0.2); # without this many tasty crashes even on latest perls
    }) || do {
      skip "EAGAIN encountered, your system is likely bogged down: skipping rest of test", 1
        if $! == Errno::EAGAIN();

      die "Unable to start thread: $!";
    };
  }
}

ok(1, "past spawning");

$_->join for @threads;

ok(1, "past joining");

# Too many threading bugs on exit, none of which have anything to do with
# the actual stuff we test
$ENV{DBICTEST_DIRTY_EXIT} = 1
  if "$]"< 5.012;

done_testing;

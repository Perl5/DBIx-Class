BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use Config;
BEGIN {
  unless ($Config{useithreads}) {
    print "1..0 # SKIP your perl does not support ithreads\n";
    exit 0;
  }

  if ($INC{'Devel/Cover.pm'}) {
    print "1..0 # SKIP Devel::Cover does not work with threads yet\n";
    exit 0;
  }
}
use threads;

use strict;
use warnings;
use Test::More;
use Errno ();
use DBIx::Class::_Util 'sigwarn_silencer';
use Time::HiRes qw(time sleep);

use DBICTest;

plan skip_all => 'DBIC does not actively support threads before perl 5.8.5'
  if "$]" < 5.008005;

plan skip_all => 'Potential problems on Win32 Perl < 5.14 and Variable::Magic - investigation pending'
  if $^O eq 'MSWin32' && "$]" < 5.014 && DBICTest::RunMode->is_plain;

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

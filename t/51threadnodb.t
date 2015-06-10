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
use DBIx::Class::_Util 'sigwarn_silencer';

use lib qw(t/lib);
use DBICTest;

plan skip_all => 'DBIC does not actively support threads before perl 5.8.5'
  if $] < '5.008005';

plan skip_all => 'Potential problems on Win32 Perl < 5.14 and Variable::Magic - investigation pending'
  if $^O eq 'MSWin32' && $] < 5.014 && DBICTest::RunMode->is_plain;

# README: If you set the env var to a number greater than 10,
#   we will use that many children
my $num_children = $ENV{DBICTEST_THREAD_STRESS} || 1;
if($num_children !~ /^[0-9]+$/ || $num_children < 10) {
   $num_children = 10;
}

my $schema = DBICTest->init_schema(no_deploy => 1);
isa_ok ($schema, 'DBICTest::Schema');

my @threads;
SKIP: {

  local $SIG{__WARN__} = sigwarn_silencer( qr/Thread creation failed/i );

  for (1.. $num_children) {
    push @threads, threads->create(sub {
      my $rsrc = $schema->source('Artist');
      undef $schema;
      isa_ok ($rsrc->schema, 'DBICTest::Schema');
      my $s2 = $rsrc->schema->clone;

      sleep 1;  # without this many tasty crashes
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

done_testing;

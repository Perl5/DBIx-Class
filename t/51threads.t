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

use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_rdbms_pg';

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Time::HiRes qw(time sleep);
use List::Util 'max';

plan skip_all => 'DBIC does not actively support threads before perl 5.8.5'
  if "$]" < 5.008005;


use DBICTest;

# README: If you set the env var to a number greater than 5,
#   we will use that many children
my $num_children = $ENV{DBICTEST_THREAD_STRESS} || 1;
if($num_children !~ /^[0-9]+$/ || $num_children < 5) {
   $num_children = 5;
}

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, { AutoCommit => 1, RaiseError => 1, PrintError => 0 });

my $parent_rs;

lives_ok (sub {
    my $dbh = $schema->storage->dbh;

    {
        local $SIG{__WARN__} = sub {};
        eval { $dbh->do("DROP TABLE cd") };
        $dbh->do("CREATE TABLE cd (cdid serial PRIMARY KEY, artist INTEGER NOT NULL UNIQUE, title VARCHAR(100) NOT NULL UNIQUE, year VARCHAR(100) NOT NULL, genreid INTEGER, single_track INTEGER);");
    }

    $schema->resultset('CD')->create({ title => 'vacation in antarctica', artist => 123, year => 1901 });
    $schema->resultset('CD')->create({ title => 'vacation in antarctica part 2', artist => 456, year => 1901 });

    $parent_rs = $schema->resultset('CD')->search({ year => 1901 });
    is ($parent_rs->count, 2);
}, 'populate successfull');

# basic tests
{
  ok ($schema->storage->connected(), 'Parent is connected');
  is ($parent_rs->next->id, 1, 'Cursor advanced');
  my $ct_num = Test::More->builder->current_test;

  my $newthread = async {
    my $out = '';

    #simulate a  subtest to not confuse the parent TAP emission
    my $tb = Test::More->builder;
    $tb->reset;
    for (qw/output failure_output todo_output/) {
      close $tb->$_;
      open ($tb->$_, '>', \$out);
    }

    ok(!$schema->storage->connected, "storage->connected() false in child");
    for (1,2) {
      throws_ok { $parent_rs->next } qr/\QMulti-thread access attempted while cursor in progress (position 1)/;
    }

    $parent_rs->reset;
    is($parent_rs->next->id, 1, 'Resetting cursor reprepares it within child environment');

    done_testing;

    close $tb->$_ for (qw/output failure_output todo_output/);
    sleep (0.2); # tasty crashes without this

    $out;
  };
  die "Thread creation failed: $! $@" if !defined $newthread;

  my $out = $newthread->join;
  $out =~ s/^/   /gm;
  print $out;

  # workaround for older Test::More confusing the plan under threads
  Test::More->builder->current_test($ct_num);

  is ($parent_rs->next->id, 2, 'Cursor still intact in parent');
  is ($parent_rs->next, undef, 'Cursor exhausted');
}

$parent_rs->reset;

# sleep until this spot so everything starts simultaneously
# add "until turn of second" for prettier display
my $t = int( time() ) + 4;

my @children;
while(@children < $num_children) {

    my $newthread = async {
        my $tid = threads->tid;

        sleep( max( 0.1, $t - time ) );

        # FIXME if we do not stagger the threads, sparks fly due to CXSA
        sleep ( $tid / 10 ) if "$]" < 5.012;

        note ("Thread $tid starting work at " . time() );

        my $child_rs = $schema->resultset('CD')->search({ year => 1901 });
        my $row = $parent_rs->next;
        if($row && $row->get_column('artist') =~ /^(?:123|456)$/) {
            $schema->resultset('CD')->create({ title => "test success $tid", artist => $tid, year => scalar(@children) });
        }

        sleep (0.2); # without this many tasty crashes even on latest perls
    };
    die "Thread creation failed: $! $@" if !defined $newthread;
    push(@children, $newthread);
}

ok(1, "past spawning");

my @tids;
for (@children) {
  push @tids, $_->tid;
  $_->join;
}

ok(1, "past joining");

while (@tids) {
    my $tid = pop @tids;
    my $rs = $schema->resultset('CD')->search({ title => "test success $tid", artist => $tid, year => scalar(@tids) });
    is($rs->next->get_column('artist'), $tid, "Child $tid successful");
}

ok(1, "Made it to the end");
undef $parent_rs;

$schema->storage->dbh->do("DROP TABLE cd");

# Too many threading bugs on exit, none of which have anything to do with
# the actual stuff we test
$ENV{DBICTEST_DIRTY_EXIT} = 1
  if "$]" < 5.012;

done_testing;

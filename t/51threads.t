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
use Test::Exception;

plan skip_all => 'DBIC does not actively support threads before perl 5.8.5'
  if $] < '5.008005';

use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('rdbms_pg')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('rdbms_pg');

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};
plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
      . ' (note: creates and drops a table named artist!)' unless ($dsn && $user);

# README: If you set the env var to a number greater than 10,
#   we will use that many children
my $num_children = $ENV{DBICTEST_THREAD_STRESS} || 1;
if($num_children !~ /^[0-9]+$/ || $num_children < 10) {
   $num_children = 10;
}

use_ok('DBICTest::Schema');

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
    sleep(1); # tasty crashes without this

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
my @children;
while(@children < $num_children) {

    my $newthread = async {
        my $tid = threads->tid;

        my $child_rs = $schema->resultset('CD')->search({ year => 1901 });
        my $row = $parent_rs->next;
        if($row && $row->get_column('artist') =~ /^(?:123|456)$/) {
            $schema->resultset('CD')->create({ title => "test success $tid", artist => $tid, year => scalar(@children) });
        }
        sleep(1); # tasty crashes without this
    };
    die "Thread creation failed: $! $@" if !defined $newthread;
    push(@children, $newthread);
}

ok(1, "past spawning");

{
    $_->join for(@children);
}

ok(1, "past joining");

while(@children) {
    my $child = pop(@children);
    my $tid = $child->tid;
    my $rs = $schema->resultset('CD')->search({ title => "test success $tid", artist => $tid, year => scalar(@children) });
    is($rs->next->get_column('artist'), $tid, "Child $tid successful");
}

ok(1, "Made it to the end");
undef $parent_rs;

$schema->storage->dbh->do("DROP TABLE cd");

done_testing;

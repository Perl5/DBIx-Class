use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;
use DBIx::Class::Optional::Dependencies ();

my $main_pid = $$;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('rdbms_pg')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('rdbms_pg');

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
      . ' (note: creates and drops a table named artist!)' unless ($dsn && $user);

# README: If you set the env var to a number greater than 10,
#   we will use that many children
my $num_children = $ENV{DBICTEST_FORK_STRESS} || 1;
if($num_children !~ /^[0-9]+$/ || $num_children < 10) {
   $num_children = 10;
}

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, { AutoCommit => 1 });

my $parent_rs;

eval {
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
};
ok(!$@) or diag "Creation eval failed: $@";

# basic tests
{
  ok ($schema->storage->connected(), 'Parent is connected');
  is ($parent_rs->next->id, 1, 'Cursor advanced');

  my ($parent_in, $child_out);
  pipe( $parent_in, $child_out ) or die "Pipe open failed: $!";

  my $pid = fork;
  if(!defined $pid) {
    die "fork failed: $!";
  }

  if (!$pid) {
    close $parent_in;

    #simulate a  subtest to not confuse the parent TAP emission
    my $tb = Test::More->builder;
    $tb->reset;
    for (qw/output failure_output todo_output/) {
      close $tb->$_;
      open ($tb->$_, '>&', $child_out);
    }

    ok(!$schema->storage->connected, "storage->connected() false in child");
    for (1,2) {
      throws_ok { $parent_rs->next } qr/\QMulti-process access attempted while cursor in progress (position 1)/;
    }

    $parent_rs->reset;
    is($parent_rs->next->id, 1, 'Resetting cursor reprepares it within child environment');

    done_testing;
    exit 0;
  }

  close $child_out;
  while (my $ln = <$parent_in>) {
    print "   $ln";
  }
  waitpid( $pid, 0 );
  ok(!$?, 'Child subtests passed');

  is ($parent_rs->next->id, 2, 'Cursor still intact in parent');
  is ($parent_rs->next, undef, 'Cursor exhausted');
}

$parent_rs->reset;
my @pids;
while(@pids < $num_children) {

    my $pid = fork;
    if(!defined $pid) {
        die "fork failed: $!";
    }
    elsif($pid) {
        push(@pids, $pid);
        next;
    }

    $pid = $$;

    my $work = sub {
      my $child_rs = $schema->resultset('CD')->search({ year => 1901 });
      my $row = $parent_rs->next;
      $schema->resultset('CD')->create({ title => "test success $pid", artist => $pid, year => scalar(@pids) })
        if($row && $row->get_column('artist') =~ /^(?:123|456)$/);
    };

    # try with and without transactions
    if ((@pids % 3) == 1) {
      my $guard = $schema->txn_scope_guard;
      $work->();
      $guard->commit;
    }
    elsif ((@pids % 3) == 2) {
      $schema->txn_do ($work);
    }
    else {
      $work->();
    }

    sleep(3);
    exit 0;
}

ok(1, "past forking");

for (@pids) {
  waitpid($_,0);
  ok (! $?, "Child $_ exitted cleanly");
};

ok(1, "past waiting");

while(@pids) {
    my $pid = pop(@pids);
    my $rs = $schema->resultset('CD')->search({ title => "test success $pid", artist => $pid, year => scalar(@pids) });
    is($rs->next->get_column('artist'), $pid, "Child $pid successful");
}

ok(1, "Made it to the end");

done_testing;

END {
  $schema->storage->dbh->do("DROP TABLE cd") if ($schema and $main_pid == $$);
  undef $schema;
}

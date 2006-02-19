use Class::C3;
use strict;
use Test::More;
use warnings;

# This test passes no matter what in most cases.  However, prior to the recent
# fork-related fixes, it would spew lots of warnings.  I have not quite gotten
# it to where it actually fails in those cases.

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_FORK_STRESS} to run this test'
    unless $ENV{DBICTEST_FORK_STRESS};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
      . ' (note: creates and drops a table named artist!)' unless ($dsn && $user);

plan tests => 15;

use lib qw(t/lib);

use_ok('DBICTest::Schema');

DBICTest::Schema->compose_connection('PgTest' => $dsn, $user, $pass, { AutoCommit => 1 });

my ($first_rs, $joe_record);

eval {
    my $dbh = PgTest->schema->storage->dbh;

    $dbh->do("CREATE TABLE cd (cdid serial PRIMARY KEY, artist INTEGER NOT NULL UNIQUE, title VARCHAR(255) NOT NULL UNIQUE, year VARCHAR(255));");

    PgTest->resultset('CD')->create({ title => 'vacation in antarctica', artist => 123, year => 1901 });
    PgTest->resultset('CD')->create({ title => 'vacation in antarctica part 2', artist => 456, year => 1901 });

    $first_rs = PgTest->resultset('CD')->search({ year => 1901 });
    $joe_record = $first_rs->next;
};
ok(!$@) or diag "Creation eval failed: $@";

my $num_children = 10;
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
    my ($forked_rs, $joe_forked);

    $forked_rs = PgTest->resultset('CD')->search({ year => 1901 });
    $joe_forked = $first_rs->next;
    if($joe_forked && $joe_forked->get_column('artist') =~ /^(?:123|456)$/) {
        PgTest->resultset('CD')->create({ title => "test success $pid", artist => $pid, year => scalar(@pids) });
    }
    sleep(3);
    exit;
}

ok(1, "past forking");

waitpid($_,0) for(@pids);

ok(1, "past waiting");

while(@pids) {
    my $pid = pop(@pids);
    my $rs = PgTest->resultset('CD')->search({ title => "test success $pid", artist => $pid, year => scalar(@pids) });
    is($rs->next->get_column('artist'), $pid, "Child $pid successful");
}

ok(1, "Made it to the end");

PgTest->schema->storage->dbh->do("DROP TABLE cd");

BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

# README: If you set the env var to a number greater than 5,
#   we will use that many children

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

plan skip_all => 'DBIC does not actively support threads before perl 5.8.5'
  if "$]" < 5.008005;

use Scalar::Util 'weaken';
use Time::HiRes qw(time sleep);
use List::Util 'max';

use DBICTest;

my $num_children = $ENV{DBICTEST_THREAD_STRESS} || 1;
if($num_children !~ /^[0-9]+$/ || $num_children < 5) {
   $num_children = 5;
}

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, { AutoCommit => 1, RaiseError => 1, PrintError => 0 });

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

        weaken(my $weak_schema = $schema);
        weaken(my $weak_parent_rs = $parent_rs);
        $schema->txn_do(sub {
            my $child_rs = $weak_schema->resultset('CD')->search({ year => 1901 });
            my $row = $weak_parent_rs->next;
            if($row && $row->get_column('artist') =~ /^(?:123|456)$/) {
                $weak_schema->resultset('CD')->create({ title => "test success $tid", artist => $tid, year => scalar(@children) });
            }
        });

        sleep (0.2); # without this many tasty crashes even on latest perls
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

$schema->storage->dbh->do("DROP TABLE cd");

# Too many threading bugs on exit, none of which have anything to do with
# the actual stuff we test
$ENV{DBICTEST_DIRTY_EXIT} = 1
  if "$]" < 5.012;

done_testing;

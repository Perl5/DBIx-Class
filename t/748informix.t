use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_informix')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_informix');

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_INFORMIX_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all => 'Set $ENV{DBICTEST_INFORMIX_DSN}, _USER and _PASS to run this test'
  unless $dsn;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
  auto_savepoint => 1
});

my $dbh = $schema->storage->dbh;

eval { $dbh->do("DROP TABLE artist") };
$dbh->do("CREATE TABLE artist (artistid SERIAL, name VARCHAR(255), charfield CHAR(10), rank INTEGER DEFAULT 13);");
eval { $dbh->do("DROP TABLE cd") };
$dbh->do(<<EOS);
CREATE TABLE cd (
  cdid int PRIMARY KEY,
  artist int,
  title varchar(255),
  year varchar(4),
  genreid int,
  single_track int
)
EOS
eval { $dbh->do("DROP TABLE track") };
$dbh->do(<<EOS);
CREATE TABLE track (
  trackid int,
  cd int REFERENCES cd(cdid),
  position int,
  title varchar(255),
  last_updated_on date,
  last_updated_at date,
  small_dt date
)
EOS

my $ars = $schema->resultset('Artist');
is ( $ars->count, 0, 'No rows at first' );

# test primary key handling
my $new = $ars->create({ name => 'foo' });
ok($new->artistid, "Auto-PK worked");

# test explicit key spec
$new = $ars->create ({ name => 'bar', artistid => 66 });
is($new->artistid, 66, 'Explicit PK worked');
$new->discard_changes;
is($new->artistid, 66, 'Explicit PK assigned');

# test populate
lives_ok (sub {
  my @pop;
  for (1..2) {
    push @pop, { name => "Artist_$_" };
  }
  $ars->populate (\@pop);
});

# test populate with explicit key
lives_ok (sub {
  my @pop;
  for (1..2) {
    push @pop, { name => "Artist_expkey_$_", artistid => 100 + $_ };
  }
  $ars->populate (\@pop);
});

# count what we did so far
is ($ars->count, 6, 'Simple count works');

# test LIMIT support
my $lim = $ars->search( {},
  {
    rows => 3,
    offset => 4,
    order_by => 'artistid'
  }
);
is( $lim->count, 2, 'ROWS+OFFSET count ok' );
is( $lim->all, 2, 'Number of ->all objects matches count' );

# test iterator
$lim->reset;
is( $lim->next->artistid, 101, "iterator->next ok" );
is( $lim->next->artistid, 102, "iterator->next ok" );
is( $lim->next, undef, "next past end of resultset ok" );

# test savepoints
throws_ok {
  $schema->txn_do(sub {
    eval {
      $schema->txn_do(sub {
        $ars->create({ name => 'in_savepoint' });
        die "rolling back savepoint";
      });
    };
    ok ((not $ars->search({ name => 'in_savepoint' })->first),
      'savepoint rolled back');
    $ars->create({ name => 'in_outer_txn' });
    die "rolling back outer txn";
  });
} qr/rolling back outer txn/,
  'correct exception for rollback';

ok ((not $ars->search({ name => 'in_outer_txn' })->first),
  'outer txn rolled back');

######## test with_deferred_fk_checks
lives_ok {
  $schema->storage->with_deferred_fk_checks(sub {
    $schema->resultset('Track')->create({
      trackid => 999, cd => 999, position => 1, title => 'deferred FK track'
    });
    $schema->resultset('CD')->create({
      artist => 1, cdid => 999, year => '2003', title => 'deferred FK cd'
    });
  });
} 'with_deferred_fk_checks code survived';

is eval { $schema->resultset('Track')->find(999)->title }, 'deferred FK track',
 'code in with_deferred_fk_checks worked';

throws_ok {
  $schema->resultset('Track')->create({
    trackid => 1, cd => 9999, position => 1, title => 'Track1'
  });
} qr/constraint/i, 'with_deferred_fk_checks is off';

done_testing;

# clean up our mess
END {
    my $dbh = eval { $schema->storage->_dbh };
    $dbh->do("DROP TABLE artist") if $dbh;
}

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use Time::HiRes 'time';
use Config;

use lib qw(t/lib);
use DBICTest;

# savepoints test
{
  my $schema = DBICTest->init_schema(auto_savepoint => 1);

  my $ars = $schema->resultset('Artist');

  # test two-phase commit and inner transaction rollback from nested transactions
  $schema->txn_do(sub {
    $ars->create({ name => 'in_outer_transaction' });
    $schema->txn_do(sub {
      $ars->create({ name => 'in_inner_transaction' });
    });
    ok($ars->search({ name => 'in_inner_transaction' })->first,
      'commit from inner transaction visible in outer transaction');
    throws_ok {
      $schema->txn_do(sub {
        $ars->create({ name => 'in_inner_transaction_rolling_back' });
        die 'rolling back inner transaction';
      });
    } qr/rolling back inner transaction/, 'inner transaction rollback executed';
    $ars->create({ name => 'in_outer_transaction2' });
  });

  ok($ars->search({ name => 'in_outer_transaction' })->first,
    'commit from outer transaction');
  ok($ars->search({ name => 'in_outer_transaction2' })->first,
    'second commit from outer transaction');
  ok($ars->search({ name => 'in_inner_transaction' })->first,
    'commit from inner transaction');
  is $ars->search({ name => 'in_inner_transaction_rolling_back' })->first,
    undef,
    'rollback from inner transaction';
}

# check that we work somewhat OK with braindead SQLite transaction handling
#
# As per https://metacpan.org/source/ADAMK/DBD-SQLite-1.37/lib/DBD/SQLite.pm#L921
# SQLite does *not* try to synchronize

for my $prefix_comment (qw/Begin_only Commit_only Begin_and_Commit/) {
  note "Testing with comment prefixes on $prefix_comment";

  # FIXME warning won't help us for the time being
  # perhaps when (if ever) DBD::SQLite gets fixed,
  # we can do something extra here
  local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /Internal transaction state .+? does not seem to match/ }
    unless $ENV{TEST_VERBOSE};

  my ($c_begin, $c_commit) = map { $prefix_comment =~ $_ ? 1 : 0 } (qr/Begin/, qr/Commit/);

  my $schema = DBICTest->init_schema( no_deploy => 1 );
  my $ars = $schema->resultset('Artist');

  ok (! $schema->storage->connected, 'No connection yet');

  $schema->storage->dbh->do(<<'DDL');
CREATE TABLE artist (
  artistid INTEGER PRIMARY KEY NOT NULL,
  name varchar(100),
  rank integer DEFAULT 13,
  charfield char(10) NULL
);
DDL

  my $artist = $ars->create({ name => 'Artist_' . time() });
  is ($ars->count, 1, 'Inserted artist ' . $artist->name);

  ok ($schema->storage->connected, 'Connected');
  ok ($schema->storage->_dbh->{AutoCommit}, 'DBD not in txn yet');

  $schema->storage->dbh->do(join "\n",
    $c_begin ? '-- comment' : (),
    'BEGIN TRANSACTION'
  );
  ok ($schema->storage->connected, 'Still connected');
  {
    local $TODO = 'SQLite is retarded wrt detecting BEGIN' if $c_begin;
    ok (! $schema->storage->_dbh->{AutoCommit}, "DBD aware of txn begin with comments on $prefix_comment");
  }

  $schema->storage->dbh->do(join "\n",
    $c_commit ? '-- comment' : (),
    'COMMIT'
  );
  ok ($schema->storage->connected, 'Still connected');
  {
    local $TODO = 'SQLite is retarded wrt detecting COMMIT' if $c_commit and ! $c_begin;
    ok ($schema->storage->_dbh->{AutoCommit}, "DBD aware txn ended with comments on $prefix_comment");
  }

  is ($ars->count, 1, 'Inserted artists still there');

  {
    # this never worked in the 1st place
    local $TODO = 'SQLite is retarded wrt detecting COMMIT' if ! $c_begin and $c_commit;

    # odd argument passing, because such nested crefs leak on 5.8
    lives_ok {
      $schema->storage->txn_do (sub {
        ok ($_[0]->find({ name => $_[1] }), "Artist still where we left it after cycle with comments on $prefix_comment");
      }, $ars, $artist->name );
    } "Succesfull transaction with comments on $prefix_comment";
  }
}


my $schema = DBICTest->init_schema();

# make sure the side-effects of RT#67581 do not result in data loss
my $row;
warnings_exist { $row = $schema->resultset('Artist')->create ({ name => 'alpha rank', rank => 'abc' }) }
  [qr/Non-numeric value supplied for column 'rank' despite the numeric datatype/],
  'proper warning on string insertion into an numeric column'
;
$row->discard_changes;
is ($row->rank, 'abc', 'proper rank inserted into database');

# and make sure we do not lose actual bigints
{
  package DBICTest::BigIntArtist;
  use base 'DBICTest::Schema::Artist';
  __PACKAGE__->table('artist');
  __PACKAGE__->add_column(bigint => { data_type => 'bigint' });
}
$schema->register_class(BigIntArtist => 'DBICTest::BigIntArtist');
$schema->storage->dbh_do(sub {
  $_[1]->do('ALTER TABLE artist ADD COLUMN bigint BIGINT');
});

# test upper/lower boundaries for sqlite and some values inbetween
# range is -(2**63) .. 2**63 - 1
SKIP: {
  skip 'This perl does not seem to have 64bit int support - DBI roundtrip of large int will fail with DBD::SQLite < 1.37', 1
    if ($Config{ivsize} < 8 and ! eval { DBD::SQLite->VERSION(1.37); 1 });

  for my $bi (qw/
    -9223372036854775808
    -9223372036854775807
    -8694837494948124658
    -6848440844435891639
    -5664812265578554454
    -5380388020020483213
    -2564279463598428141
    2442753333597784273
    4790993557925631491
    6773854980030157393
    7627910776496326154
    8297530189347439311
    9223372036854775806
    9223372036854775807
  /) {
    $row = $schema->resultset('BigIntArtist')->create({ bigint => $bi });
    is ($row->bigint, $bi, "value in object correct ($bi)");

    $row->discard_changes;
    is ($row->bigint, $bi, "value in database correct ($bi)");
  }
}

done_testing;

# vim:sts=2 sw=2:

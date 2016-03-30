use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use Time::HiRes 'time';
use Math::BigInt;

use lib qw(t/lib);
use DBICTest;
use DBIx::Class::_Util qw( sigwarn_silencer modver_gt_or_eq modver_gt_or_eq_and_lt );

# make one deploy() round before we load anything else - need this in order
# to prime SQLT if we are using it (deep depchain is deep)
DBICTest->init_schema( no_populate => 1 );

# check that we work somewhat OK with braindead SQLite transaction handling
#
# As per https://metacpan.org/source/ADAMK/DBD-SQLite-1.37/lib/DBD/SQLite.pm#L921
# SQLite does *not* try to synchronize
#
# However DBD::SQLite 1.38_02 seems to fix this, with an accompanying test:
# https://metacpan.org/source/ADAMK/DBD-SQLite-1.38_02/t/54_literal_txn.t
my $lit_txn_todo = modver_gt_or_eq('DBD::SQLite', '1.38_02')
  ? undef
  : "DBD::SQLite before 1.38_02 is retarded wrt detecting literal BEGIN/COMMIT statements"
;

for my $prefix_comment (qw/Begin_only Commit_only Begin_and_Commit/) {
  note "Testing with comment prefixes on $prefix_comment";

  # FIXME warning won't help us for the time being
  # perhaps when (if ever) DBD::SQLite gets fixed,
  # we can do something extra here
  local $SIG{__WARN__} = sigwarn_silencer( qr/Internal transaction state .+? does not seem to match/ )
    if ( $lit_txn_todo && !$ENV{TEST_VERBOSE} );

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
    local $TODO = $lit_txn_todo if $c_begin;
    ok (! $schema->storage->_dbh->{AutoCommit}, "DBD aware of txn begin with comments on $prefix_comment");
  }

  $schema->storage->dbh->do(join "\n",
    $c_commit ? '-- comment' : (),
    'COMMIT'
  );
  ok ($schema->storage->connected, 'Still connected');
  {
    local $TODO = $lit_txn_todo if $c_commit and ! $c_begin;
    ok ($schema->storage->_dbh->{AutoCommit}, "DBD aware txn ended with comments on $prefix_comment");
  }

  is ($ars->count, 1, 'Inserted artists still there');

  {
    # this never worked in the 1st place
    local $TODO = $lit_txn_todo if ! $c_begin and $c_commit;

    # odd argument passing, because such nested crefs leak on 5.8
    lives_ok {
      $schema->storage->txn_do (sub {
        ok ($_[0]->find({ name => $_[1] }), "Artist still where we left it after cycle with comments on $prefix_comment");
      }, $ars, $artist->name );
    } "Succesfull transaction with comments on $prefix_comment";
  }
}

# test blank begin/svp/commit/begin cycle
#
# need to prime this for exotic testing scenarios
# before testing for lack of warnings
modver_gt_or_eq('DBD::SQLite', '1.33');

warnings_are {
  my $schema = DBICTest->init_schema( no_populate => 1 );
  my $rs = $schema->resultset('Artist');
  is ($rs->count, 0, 'Start with empty table');

  for my $do_commit (1, 0) {
    $schema->txn_begin;
    $schema->svp_begin;
    $schema->svp_rollback;

    $schema->svp_begin;
    $schema->svp_rollback;

    $schema->svp_release;

    $schema->svp_begin;

    $schema->txn_rollback;

    $schema->txn_begin;
    $schema->svp_begin;
    $schema->svp_rollback;

    $schema->svp_begin;
    $schema->svp_rollback;

    $schema->svp_release;

    $schema->svp_begin;

    $do_commit ? $schema->txn_commit : $schema->txn_rollback;

    is_deeply $schema->storage->savepoints, [], 'Savepoint names cleared away'
  }

  $schema->txn_do(sub {
    ok (1, 'all seems fine');
  });
} [], 'No warnings emitted';

my $schema = DBICTest->init_schema();

# make sure the side-effects of RT#67581 do not result in data loss
my $row;
warnings_exist { $row = $schema->resultset('Artist')->create ({ name => 'alpha rank', rank => 'abc' }) }
  [qr/Non-integer value supplied for column 'rank' despite the integer datatype/],
  'proper warning on string insertion into an numeric column'
;
$row->discard_changes;
is ($row->rank, 'abc', 'proper rank inserted into database');

# and make sure we do not lose actual bigints
SKIP: {

skip "Not testing bigint handling on known broken DBD::SQLite trial versions", 1
  if( modver_gt_or_eq('DBD::SQLite', '1.45') and ! modver_gt_or_eq('DBD::SQLite', '1.45_03') );

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

my $sqlite_broken_bigint = modver_gt_or_eq_and_lt( 'DBD::SQLite', '1.34', '1.37' );

# 63 bit integer
my $many_bits = (Math::BigInt->new(2) ** 62);

# test upper/lower boundaries for sqlite and some values inbetween
# range is -(2**63) .. 2**63 - 1
#
# Not testing -0 - it seems to overflow to ~0 on some combinations,
# thus not triggering the >32 bit guards
# interesting read: https://en.wikipedia.org/wiki/Signed_zero#Representations
for my $bi ( qw(
  -2
  -1
  0
  +0
  1
  2

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

  4294967295
  4294967296

  -4294967296
  -4294967295
  -4294967294

  -2147483649
  -2147483648
  -2147483647
  -2147483646

  2147483646
  2147483647
),
  # these values cause exceptions even with all workarounds in place on these
  # fucked DBD::SQLite versions *regardless* of ivsize >.<
  $sqlite_broken_bigint
    ? ()
    : ( '2147483648', '2147483649' )
  ,

  # with newer compilers ( gcc 4.9+ ) older DBD::SQLite does not
  # play well with the "Most Negative Number"
  modver_gt_or_eq( 'DBD::SQLite', '1.33' )
    ? ( '-9223372036854775808' )
    : ()
  ,

) {
  # unsigned 32 bit ints have a range of −2,147,483,648 to 2,147,483,647
  # alternatively expressed as the hexadecimal numbers below
  # the comparison math will come out right regardless of ivsize, since
  # we are operating within 31 bits
  # P.S. 31 because one bit is lost for the sign
  my $v_bits = ($bi > 0x7fff_ffff || $bi < -0x8000_0000) ? 64 : 32;

  my $v_desc = sprintf '%s (%d bit signed int)', $bi, $v_bits;

  my @w;
  local $SIG{__WARN__} = sub {
    if ($_[0] =~ /datatype mismatch/) {
      push @w, @_;
    }
    elsif ($_[0] =~ /An integer value occupying more than 32 bits was supplied .+ can not bind properly so DBIC will treat it as a string instead/ ) {
      # do nothing, this warning will pop up here and there depending on
      # DBD/bitness combination
      # we don't want to test for it explicitly, we are just interested
      # in the results matching at the end
    }
    else {
      warn @_;
    }
  };

  # some combinations of SQLite 1.35 and older 5.8 faimly is wonky
  # instead of a warning we get a full exception. Sod it
  eval {
    $row = $schema->resultset('BigIntArtist')->create({ bigint => $bi });
  } or do {
    fail("Exception on inserting $v_desc: $@") unless $sqlite_broken_bigint;
    next;
  };

  # explicitly using eq, to make sure we did not nummify the argument
  # which can be an issue on 32 bit ivsize
  cmp_ok ($row->bigint, 'eq', $bi, "value in object correct ($v_desc)");

  $row->discard_changes;

  cmp_ok (
    $row->bigint,

    # the test will not pass an == if we are running under 32 bit ivsize
    # use 'eq' on the numified (and possibly "scientificied") returned value
    (DBIx::Class::_ENV_::IV_SIZE < 8 and $v_bits > 32) ? 'eq' : '==',

    # in 1.37 DBD::SQLite switched to proper losless representation of bigints
    # regardless of ivize
    # before this use 'eq' (from above) on the numified (and possibly
    # "scientificied") returned value
    (DBIx::Class::_ENV_::IV_SIZE < 8 and ! modver_gt_or_eq('DBD::SQLite', '1.37')) ? $bi+0 : $bi,

    "value in database correct ($v_desc)"
  );

# FIXME - temporary smoke-only escape
SKIP: {
  skip 'Potential for false negatives - investigation pending', 1
    if DBICTest::RunMode->is_plain;

  # check if math works
  # start by adding/subtracting a 50 bit integer, and then divide by 2 for good measure
  my ($sqlop, $expect) = $bi < 0
    ? ( '(bigint + ? )', ($bi + $many_bits) )
    : ( '(bigint - ? )', ($bi - $many_bits) )
  ;

  $expect = ($expect + ($expect % 2)) / 2;

  # read https://en.wikipedia.org/wiki/Modulo_operation#Common_pitfalls
  # and check the tables on the right side of the article for an
  # enlightening journey on why a mere bigint % 2 won't work
  $sqlop = "( $sqlop + ( ((bigint % 2)+2)%2 ) ) / 2";

  for my $dtype (undef, \'int', \'bigint') {

    # FIXME - the double-load should not be needed
    # will fix in the future
    $row->update({ bigint => $bi });
    $row->discard_changes;
    $row->update({ bigint => \[ $sqlop, [ $dtype => $many_bits ] ] });
    $row->discard_changes;

    # can't use cmp_ok - will not engage the M::BI overload of $many_bits
    ok (
      $row->bigint

      ==

      (DBIx::Class::_ENV_::IV_SIZE < 8 and ! modver_gt_or_eq('DBD::SQLite', '1.37')) ? $expect->bstr + 0 : $expect
    , "simple integer math with@{[ $dtype ? '' : 'out' ]} bindtype in database correct (base $v_desc)")
      or diag sprintf '%s != %s', $row->bigint, $expect;
  }
# end of fixme
}

  is_deeply (\@w, [], "No mismatch warnings on bigint operations ($v_desc)" );

}}

done_testing;

# vim:sts=2 sw=2:

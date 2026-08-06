use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

# A connection dying while a transaction is in progress used to leave the
# storage permanently poisoned: the failed commit/rollback never got to
# decrement transaction_depth, and from then on dbh_do's "we are inside a
# transaction" short circuit skipped the ping/reconnect/retry machinery
# entirely, running every subsequent query on the dead cached $dbh.
#
# The transaction itself failing is expected and unavoidable. What is tested
# here is that the storage does not stay wedged afterwards.

my $schema = DBICTest->init_schema( sqlite_use_file => 1 );

my $artist_count = $schema->resultset('Artist')->count;
cmp_ok ($artist_count, '>', 0, 'sanity check - artists in the test schema');

# Kill the connection behind DBIC's back, the way a server-side death does.
sub murder_connection {
  # DBD::SQLite grumbles about disconnecting mid-transaction, which is
  # precisely what we are simulating
  local $SIG{__WARN__} = sub {};
  $schema->storage->_dbh->disconnect;
}

# Both halves matter, and they are asserted separately on purpose:
#   - the bookkeeping now reflects reality (nothing to commit or roll back)
#   - the *same* storage object services the next query
# Note the recovery query deliberately goes through the normal resultset path
# (i.e. dbh_do). Asserting via ->dbh or ->ensure_connected would prove nothing:
# both ping and reconnect even on a wedged storage, healing it themselves.
sub assert_storage_recovered {
  my $desc = shift;

  is ($schema->storage->transaction_depth, 0, "$desc: transaction_depth reset");

  my $count;
  lives_ok { $count = $schema->resultset('Artist')->count }
    "$desc: storage reconnects for subsequent queries";
  is ($count, $artist_count, "$desc: correct results after recovery");
}

# Drivers defer the actual BEGIN until the transaction's first statement, so a
# transaction that never issues one unwinds entirely client-side and cannot
# reproduce any of this. Every case below runs a statement before the kill.
sub statement_within_txn {
  $schema->resultset('Artist')->count;
}

# Deliberately bypasses everything under test here: each case starts from a
# known-good storage, so that a case which fails (i.e. leaves the storage
# wedged) cannot cascade into meaningless failures in the ones after it.
sub start_from_clean_storage {
  local $SIG{__WARN__} = sub {};
  $schema->storage->_dbh(undef);
  $schema->storage->transaction_depth(0);
  $schema->storage->savepoints([]);
  $schema->storage->ensure_connected;
}

subtest 'failed txn_commit on a dead connection' => sub {
  start_from_clean_storage();
  $schema->txn_begin;
  statement_within_txn();
  murder_connection();

  dies_ok { $schema->txn_commit } 'commit on a dead connection throws';

  assert_storage_recovered('manual txn_commit');
};

subtest 'failed txn_rollback on a dead connection' => sub {
  start_from_clean_storage();
  $schema->txn_begin;
  statement_within_txn();
  murder_connection();

  dies_ok { $schema->txn_rollback } 'rollback on a dead connection throws';

  assert_storage_recovered('manual txn_rollback');
};

# The production case: TxnScopeGuard::commit marks the guard inactivated
# *before* calling txn_commit (RT#107159), so a failure here means DESTROY
# returns early - no rollback attempt, no warning, nothing to reset the depth.
# DBIC opens these guards internally for populate/update_all/delete_all, so
# this wedge can happen without any transaction being visible in user code.
subtest 'failed txn_scope_guard commit on a dead connection' => sub {
  start_from_clean_storage();

  my @warnings;

  {
    my $guard = $schema->txn_scope_guard;
    statement_within_txn();
    murder_connection();

    dies_ok { $guard->commit } 'guard commit on a dead connection throws';

    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    undef $guard;
  }

  is_deeply (\@warnings, [], 'no second rollback attempt on guard destruction');

  assert_storage_recovered('txn_scope_guard commit');
};

subtest 'txn_scope_guard destruction on a dead connection' => sub {
  start_from_clean_storage();

  my @warnings;

  {
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $guard = $schema->txn_scope_guard;
    statement_within_txn();
    murder_connection();
  }

  ok (
    (grep { $_ =~ /went out of scope without explicit commit/ } @warnings),
    'uncommitted guard still warns on destruction'
  );

  assert_storage_recovered('txn_scope_guard destruction');
};

# The cases above all lose the connection outright, so the failure surfaces
# from the "disconnected storage" guards in Storage::DBI. When the handle has
# not yet noticed the death, the failure comes out of the commit/rollback exec
# itself instead - that path needs the same treatment.
subtest 'connection dying during the commit exec itself' => sub {
  start_from_clean_storage();
  $schema->txn_begin;
  statement_within_txn();

  {
    no warnings 'redefine';
    local *DBIx::Class::Storage::DBI::_exec_txn_commit = sub {
      murder_connection();
      die "simulated connection loss during commit\n";
    };

    throws_ok { $schema->txn_commit } qr/simulated connection loss during commit/,
      'the original exception propagates, not a bookkeeping error';
  }

  assert_storage_recovered('commit exec failure');
};

# Conversely: a commit/rollback can fail with the connection perfectly alive,
# in which case the server session may genuinely still hold an (aborted)
# transaction. Zeroing the depth there would let subsequent statements run
# inside a zombie transaction, so the bookkeeping must be left alone.
#
# Kept last, since it deliberately leaves the storage mid-transaction.
subtest 'failed rollback on a live connection does not reset bookkeeping' => sub {
  start_from_clean_storage();
  $schema->txn_begin;
  statement_within_txn();

  {
    no warnings 'redefine';
    local *DBIx::Class::Storage::DBI::_exec_txn_rollback = sub {
      die "simulated rollback failure\n";
    };

    throws_ok { $schema->txn_rollback } qr/simulated rollback failure/,
      'the rollback failure propagates';
  }

  ok ($schema->storage->connected, 'connection is still alive');
  is ($schema->storage->transaction_depth, 1,
    'transaction_depth left intact while the session may still be in a txn');
};

# the negative case above leaves a transaction open on purpose - do not carry
# that into global destruction
start_from_clean_storage();
$schema->storage->disconnect;

# the helper subs above close over $schema, which would otherwise keep it alive
# past the point where DBICTest checks for leaks
undef $schema;

done_testing;

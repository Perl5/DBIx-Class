use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBIx::Class::Optional::Dependencies;
use DBIx::Class::_Util qw(sigwarn_silencer scope_guard);
use Scalar::Util 'weaken';

use lib qw(t/lib);
use DBICTest;

{
  package # moar hide
    DBICTest::SVPTracerObj;

  use base 'DBIx::Class::Storage::Statistics';

  sub query_start { 'do notning'}
  sub callback { 'dummy '}

  for my $svpcall (map { "svp_$_" } qw(begin rollback release)) {
    no strict 'refs';
    *$svpcall = sub { $_[0]{uc $svpcall}++ };
  }
}

my $env2optdep = {
  DBICTEST_PG => 'test_rdbms_pg',
  DBICTEST_MYSQL => 'test_rdbms_mysql',
};

my $schema;

for ('', keys %$env2optdep) { SKIP: {

  my $prefix;

  if ($prefix = $_) {
    my ($dsn, $user, $pass) = map { $ENV{"${prefix}_$_"} } qw/DSN USER PASS/;

    skip ("Skipping tests with $prefix: set \$ENV{${prefix}_DSN} _USER and _PASS", 1)
      unless $dsn;

    skip ("Testing with ${prefix}_DSN needs " . DBIx::Class::Optional::Dependencies->req_missing_for( $env2optdep->{$prefix} ), 1)
      unless  DBIx::Class::Optional::Dependencies->req_ok_for($env2optdep->{$prefix});

    $schema = DBICTest::Schema->connect ($dsn,$user,$pass,{ auto_savepoint => 1 });

    my $create_sql;
    $schema->storage->ensure_connected;
    if ($schema->storage->isa('DBIx::Class::Storage::DBI::Pg')) {
      $create_sql = "CREATE TABLE artist (artistid serial PRIMARY KEY, name VARCHAR(100), rank INTEGER NOT NULL DEFAULT '13', charfield CHAR(10))";
      $schema->storage->dbh->do('SET client_min_messages=WARNING');
    }
    elsif ($schema->storage->isa('DBIx::Class::Storage::DBI::mysql')) {
      $create_sql = "CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), rank INTEGER NOT NULL DEFAULT '13', charfield CHAR(10)) ENGINE=InnoDB";
    }
    else {
      skip( 'Untested driver ' . $schema->storage, 1 );
    }

    $schema->storage->dbh_do (sub {
      $_[1]->do('DROP TABLE IF EXISTS artist');
      $_[1]->do($create_sql);
    });
  }
  else {
    $prefix = 'SQLite Internal DB';
    $schema = DBICTest->init_schema( no_populate => 1, auto_savepoint => 1 );
  }

  note "Testing $prefix";

  local $schema->storage->{debugobj} = my $stats = DBICTest::SVPTracerObj->new;
  local $schema->storage->{debug} = 1;

  $schema->resultset('Artist')->create({ name => 'foo' });

  $schema->txn_begin;

  my $arty = $schema->resultset('Artist')->find(1);

  my $name = $arty->name;

  # First off, test a generated savepoint name
  $schema->svp_begin;

  cmp_ok($stats->{'SVP_BEGIN'}, '==', 1, 'Statistics svp_begin tickled');

  $arty->update({ name => 'Jheephizzy' });

  $arty->discard_changes;

  cmp_ok($arty->name, 'eq', 'Jheephizzy', 'Name changed');

  # Rollback the generated name
  # Active: 0
  $schema->svp_rollback;

  cmp_ok($stats->{'SVP_ROLLBACK'}, '==', 1, 'Statistics svp_rollback tickled');

  $arty->discard_changes;

  cmp_ok($arty->name, 'eq', $name, 'Name rolled back');

  $arty->update({ name => 'Jheephizzy'});

  # Active: 0 1
  $schema->svp_begin('testing1');

  $arty->update({ name => 'yourmom' });

  # Active: 0 1 2
  $schema->svp_begin('testing2');

  $arty->update({ name => 'gphat' });
  $arty->discard_changes;
  cmp_ok($arty->name, 'eq', 'gphat', 'name changed');

  # Active: 0 1 2
  # Rollback doesn't DESTROY the savepoint, it just rolls back to the value
  # at its conception
  $schema->svp_rollback('testing2');
  $arty->discard_changes;
  cmp_ok($arty->name, 'eq', 'yourmom', 'testing2 reverted');

  # Active: 0 1 2 3
  $schema->svp_begin('testing3');
  $arty->update({ name => 'coryg' });

  # Active: 0 1 2 3 4
  $schema->svp_begin('testing4');
  $arty->update({ name => 'watson' });

  # Release 3, which implicitly releases 4
  # Active: 0 1 2
  $schema->svp_release('testing3');

  $arty->discard_changes;
  cmp_ok($arty->name, 'eq', 'watson', 'release left data');

  # This rolls back savepoint 2
  # Active: 0 1 2
  $schema->svp_rollback;

  $arty->discard_changes;
  cmp_ok($arty->name, 'eq', 'yourmom', 'rolled back to 2');

  # Rollback the original savepoint, taking us back to the beginning, implicitly
  # rolling back savepoint 1 and 2
  $schema->svp_rollback('savepoint_0');
  $arty->discard_changes;
  cmp_ok($arty->name, 'eq', 'foo', 'rolled back to start');

  $schema->txn_commit;

  is_deeply( $schema->storage->savepoints, [], 'All savepoints forgotten' );

  # And now to see if txn_do will behave correctly
  $schema->txn_do (sub {
    my $artycp = $arty;

    $schema->txn_do (sub {
      $artycp->name ('Muff');
      $artycp->update;
    });

    eval {
      $schema->txn_do (sub {
        $artycp->name ('Moff');
        $artycp->update;
        $artycp->discard_changes;
        is($artycp->name,'Moff','Value updated in nested transaction');
        $schema->storage->dbh->do ("GUARANTEED TO PHAIL");
      });
    };

    ok ($@,'Nested transaction failed (good)');

    $arty->discard_changes;

    is($arty->name,'Muff','auto_savepoint rollback worked');

    $arty->name ('Miff');

    $arty->update;
  });

  is_deeply( $schema->storage->savepoints, [], 'All savepoints forgotten' );

  $arty->discard_changes;

  is($arty->name,'Miff','auto_savepoint worked');

  cmp_ok($stats->{'SVP_BEGIN'},'==',7,'Correct number of savepoints created');

  cmp_ok($stats->{'SVP_RELEASE'},'==',3,'Correct number of savepoints released');

  cmp_ok($stats->{'SVP_ROLLBACK'},'==',5,'Correct number of savepoint rollbacks');

### test originally written for SQLite exclusively (git blame -w -C -M)
  # test two-phase commit and inner transaction rollback from nested transactions
  my $ars = $schema->resultset('Artist');

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

  is_deeply( $schema->storage->savepoints, [], 'All savepoints forgotten' );

  ok($ars->search({ name => 'in_outer_transaction' })->first,
    'commit from outer transaction');
  ok($ars->search({ name => 'in_outer_transaction2' })->first,
    'second commit from outer transaction');
  ok($ars->search({ name => 'in_inner_transaction' })->first,
    'commit from inner transaction');
  is $ars->search({ name => 'in_inner_transaction_rolling_back' })->first,
    undef,
    'rollback from inner transaction';

  # make sure a fresh txn will work after above
  $schema->storage->txn_do(sub { ok "noop" } );

### Make sure non-existend savepoint release doesn't infloop itself
  {
    weaken( my $s = $schema );

    throws_ok {
      $s->storage->txn_do(sub { $s->svp_release('wibble') })
    } qr/Savepoint 'wibble' does not exist/,
      "Calling svp_release on a non-existant savepoint throws expected error"
    ;
  }

### cleanupz
  $schema->storage->dbh->do ("DROP TABLE artist");
}}

done_testing;

END {
  eval { $schema->storage->dbh_do(sub { $_[1]->do("DROP TABLE artist") }) } if defined $schema;
  undef $schema;
}

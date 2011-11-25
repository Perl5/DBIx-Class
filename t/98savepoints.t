use strict;
use warnings;

use Test::More;
use DBIx::Class::Optional::Dependencies ();

my $env2optdep = {
  DBICTEST_PG => 'rdbms_pg',
  DBICTEST_MYSQL => 'test_rdbms_mysql',
};

plan skip_all => join (' ',
  'Set $ENV{DBICTEST_PG_DSN} and/or $ENV{DBICTEST_MYSQL_DSN} _USER and _PASS to run these tests.',
) unless grep { $ENV{"${_}_DSN"} } keys %$env2optdep;

use lib qw(t/lib);
use DBICTest;
use DBICTest::Stats;

my $schema;

for my $prefix (keys %$env2optdep) { SKIP: {
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

  note "Testing $prefix";

  my $stats = DBICTest::Stats->new;
  $schema->storage->debugobj($stats);
  $schema->storage->debug(1);

  $schema->storage->dbh->do ('DROP TABLE IF EXISTS artist');
  $schema->storage->dbh->do ($create_sql);

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
  # at it's conception
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

  # And now to see if txn_do will behave correctly
  $schema->txn_do (sub {
    $schema->txn_do (sub {
      $arty->name ('Muff');
      $arty->update;
    });

    eval {
      $schema->txn_do (sub {
        $arty->name ('Moff');
        $arty->update;
        $arty->discard_changes;
        is($arty->name,'Moff','Value updated in nested transaction');
        $schema->storage->dbh->do ("GUARANTEED TO PHAIL");
      });
    };

    ok ($@,'Nested transaction failed (good)');

    $arty->discard_changes;

    is($arty->name,'Muff','auto_savepoint rollback worked');

    $arty->name ('Miff');

    $arty->update;
  });

  $arty->discard_changes;

  is($arty->name,'Miff','auto_savepoint worked');

  cmp_ok($stats->{'SVP_BEGIN'},'==',7,'Correct number of savepoints created');

  cmp_ok($stats->{'SVP_RELEASE'},'==',3,'Correct number of savepoints released');

  cmp_ok($stats->{'SVP_ROLLBACK'},'==',5,'Correct number of savepoint rollbacks');

  $schema->storage->dbh->do ("DROP TABLE artist");
}}

done_testing;

END { eval { $schema->storage->dbh->do ("DROP TABLE artist") } if defined $schema }


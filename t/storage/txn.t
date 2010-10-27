use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Disabled on windows, pending resolution of DBD::SQLite SIGSEGVs'
  if $^O eq 'MSWin32';

my $code = sub {
  my ($artist, @cd_titles) = @_;

  $artist->create_related('cds', {
    title => $_,
    year => 2006,
  }) foreach (@cd_titles);

  return $artist->cds;
};

# Test checking of parameters
{
  my $schema = DBICTest->init_schema;

  throws_ok (sub {
    (ref $schema)->txn_do(sub{});
  }, qr/storage/, "can't call txn_do without storage");

  throws_ok ( sub {
    $schema->txn_do('');
  }, qr/must be a CODE reference/, '$coderef parameter check ok');
}

# Test successful txn_do() - scalar/list context
for my $want (0,1) {
  my $schema = DBICTest->init_schema;

  is( $schema->storage->{transaction_depth}, 0, 'txn depth starts at 0');

  my @titles = map {'txn_do test CD ' . $_} (1..5);
  my $artist = $schema->resultset('Artist')->find(1);
  my $count_before = $artist->cds->count;

  my @res;
  if ($want) {
    @res = $schema->txn_do($code, $artist, @titles);
    is(scalar @res, $count_before+5, 'successful txn added 5 cds');
  }
  else {
    $res[0] = $schema->txn_do($code, $artist, @titles);
    is($res[0], $count_before+5, 'successful txn added 5 cds');
  }

  is($artist->cds({
    title => "txn_do test CD $_",
  })->first->year, 2006, "new CD $_ year correct") for (1..5);

  is( $schema->storage->{transaction_depth}, 0, 'txn depth has been reset');
}

# Test txn_do() @_ aliasing support
{
  my $schema = DBICTest->init_schema;

  my $res = 'original';
  $schema->storage->txn_do (sub { $_[0] = 'changed' }, $res);
  is ($res, 'changed', "Arguments properly aliased for txn_do");
}

# Test nested successful txn_do()
{
  my $schema = DBICTest->init_schema;

  is( $schema->storage->{transaction_depth}, 0, 'txn depth starts at 0');

  my $nested_code = sub {
    my ($schema, $artist, $code) = @_;

    my @titles1 = map {'nested txn_do test CD ' . $_} (1..5);
    my @titles2 = map {'nested txn_do test CD ' . $_} (6..10);

    $schema->txn_do($code, $artist, @titles1);
    $schema->txn_do($code, $artist, @titles2);
  };

  my $artist = $schema->resultset('Artist')->find(2);
  my $count_before = $artist->cds->count;

  lives_ok (sub {
    $schema->txn_do($nested_code, $schema, $artist, $code);
  }, 'nested txn_do succeeded');

  is($artist->cds({
    title => 'nested txn_do test CD '.$_,
  })->first->year, 2006, qq{nested txn_do CD$_ year ok}) for (1..10);
  is($artist->cds->count, $count_before+10, 'nested txn_do added all CDs');

  is( $schema->storage->{transaction_depth}, 0, 'txn depth has been reset');
}

# test nested txn_begin on fresh connection
{
  my $schema = DBICTest->init_schema(sqlite_use_file => 1, no_deploy => 1);
  $schema->storage->ensure_connected;

  is ($schema->storage->transaction_depth, 0, 'Start outside txn');

  my @pids;
  for my $action (
    sub {
      my $s = shift;
      die "$$ starts in txn!" if $s->storage->transaction_depth != 0;
      $s->txn_do ( sub {
        die "$$ not in txn!" if $s->storage->transaction_depth == 0;
        $s->storage->dbh->do('SELECT 1') } 
      );
      die "$$ did not finish txn!" if $s->storage->transaction_depth != 0;
    },
    sub {
      $_[0]->txn_begin;
      $_[0]->storage->dbh->do('SELECT 1');
      $_[0]->txn_commit
    },
    sub {
      my $guard = $_[0]->txn_scope_guard;
      $_[0]->storage->dbh->do('SELECT 1');
      $guard->commit
    },
  ) {
    push @pids, fork();
    die "Unable to fork: $!\n"
      if ! defined $pids[-1];

    if ($pids[-1]) {
      next;
    }

    $action->($schema);
    exit 0;
  }

  is ($schema->storage->transaction_depth, 0, 'Parent still outside txn');

  for my $pid (@pids) {
    waitpid ($pid, 0);
    ok (! $?, "Child $pid exit ok");
  }
}

# Test txn_do/scope_guard with forking: outer txn_do
{
  my $schema = DBICTest->init_schema( sqlite_use_file => 1 );

  for my $pass (1..2) {

    # do something trying to destabilize the depth count
    for (1..2) {
      eval {
        my $guard = $schema->txn_scope_guard;
        $schema->txn_do( sub { die } );
      };
      $schema->txn_do( sub {
        ok ($schema->storage->_dbh->do ('SELECT 1'), "Query after exceptions ok ($_)");
      });
    }

    for my $pid ( $schema->txn_do ( sub { _forking_action ($schema) } ) ) {
      waitpid ($pid, 0);
      ok (! $?, "Child $pid exit ok (pass $pass)");
      isa_ok ($schema->resultset ('Artist')->find ({ name => "forking action $pid" }), 'DBIx::Class::Row');
    }
  }
}

# same test with outer guard
{
  my $schema = DBICTest->init_schema( sqlite_use_file => 1 );

  for my $pass (1..2) {

    # do something trying to destabilize the depth count
    for (1..2) {
      eval {
        my $guard = $schema->txn_scope_guard;
        $schema->txn_do( sub { die } );
      };
      $schema->txn_do( sub {
        ok ($schema->storage->_dbh->do ('SELECT 1'), "Query after exceptions ok ($_)");
      });
    }

    my @pids;
    my $guard = $schema->txn_scope_guard;
    _forking_action ($schema);
    $guard->commit;

    for my $pid (@pids) {
      waitpid ($pid, 0);
      ok (! $?, "Child $pid exit ok (pass $pass)");
      isa_ok ($schema->resultset ('Artist')->find ({ name => "forking action $pid" }), 'DBIx::Class::Row');
    }
  }
}

sub _forking_action {
  my $schema = shift;

  my @pids;
  while (@pids < 5) {

    push @pids, fork();
    die "Unable to fork: $!\n"
      if ! defined $pids[-1];

    if ($pids[-1]) {
      next;
    }

    if (@pids % 2) {
      $schema->txn_do (sub {
        my $depth = $schema->storage->transaction_depth;
        die "$$(txn_do)unexpected txn depth $depth!" if $depth != 1;
        $schema->resultset ('Artist')->create ({ name => "forking action $$"});
      });
    }
    else {
      my $guard = $schema->txn_scope_guard;
      my $depth = $schema->storage->transaction_depth;
      die "$$(scope_guard) unexpected txn depth $depth!" if $depth != 1;
      $schema->resultset ('Artist')->create ({ name => "forking action $$"});
      $guard->commit;
    }

    exit 0;
  }

  return @pids;
}

my $fail_code = sub {
  my ($artist) = @_;
  $artist->create_related('cds', {
    title => 'this should not exist',
    year => 2005,
  });
  die "the sky is falling";
};

{
  my $schema = DBICTest->init_schema;

  # Test failed txn_do()
  for my $pass (1,2) {

    is( $schema->storage->{transaction_depth}, 0, "txn depth starts at 0 (pass $pass)");

    my $artist = $schema->resultset('Artist')->find(3);

    throws_ok (sub {
      $schema->txn_do($fail_code, $artist);
    }, qr/the sky is falling/, "failed txn_do threw an exception (pass $pass)");

    my $cd = $artist->cds({
      title => 'this should not exist',
      year => 2005,
    })->first;
    ok(!defined($cd), qq{failed txn_do didn't change the cds table (pass $pass)});

    is( $schema->storage->{transaction_depth}, 0, "txn depth has been reset (pass $pass)");
  }


  # Test failed txn_do() with failed rollback
  {
    is( $schema->storage->{transaction_depth}, 0, 'txn depth starts at 0');

    my $artist = $schema->resultset('Artist')->find(3);

    # Force txn_rollback() to throw an exception
    no warnings 'redefine';
    no strict 'refs';

    # die in rollback
    local *{"DBIx::Class::Storage::DBI::SQLite::txn_rollback"} = sub{
      my $storage = shift;
      die 'FAILED';
    };

    throws_ok (
      sub {
        $schema->txn_do($fail_code, $artist);
      },
      qr/the sky is falling.+Rollback failed/s,
      'txn_rollback threw a rollback exception (and included the original exception'
    );

    my $cd = $artist->cds({
      title => 'this should not exist',
      year => 2005,
    })->first;
    isa_ok($cd, 'DBICTest::CD', q{failed txn_do with a failed txn_rollback }.
           q{changed the cds table});
    $cd->delete; # Rollback failed
    $cd = $artist->cds({
      title => 'this should not exist',
      year => 2005,
    })->first;
    ok(!defined($cd), q{deleted the failed txn's cd});
    $schema->storage->_dbh->rollback;
  }
}

# Test nested failed txn_do()
{
  my $schema = DBICTest->init_schema();

  is( $schema->storage->{transaction_depth}, 0, 'txn depth starts at 0');

  my $nested_fail_code = sub {
    my ($schema, $artist, $code1, $code2) = @_;

    my @titles = map {'nested txn_do test CD ' . $_} (1..5);

    $schema->txn_do($code1, $artist, @titles); # successful txn
    $schema->txn_do($code2, $artist);          # failed txn
  };

  my $artist = $schema->resultset('Artist')->find(3);

  throws_ok ( sub {
    $schema->txn_do($nested_fail_code, $schema, $artist, $code, $fail_code);
  }, qr/the sky is falling/, 'nested failed txn_do threw exception');

  ok(!defined($artist->cds({
    title => 'nested txn_do test CD '.$_,
    year => 2006,
  })->first), qq{failed txn_do didn't add first txn's cd $_}) for (1..5);
  my $cd = $artist->cds({
    title => 'this should not exist',
    year => 2005,
  })->first;
  ok(!defined($cd), q{failed txn_do didn't add failed txn's cd});
}

# Grab a new schema to test txn before connect
{
  my $schema = DBICTest->init_schema(no_deploy => 1);
  lives_ok (sub {
    $schema->txn_begin();
    $schema->txn_begin();
  }, 'Pre-connection nested transactions.');

  # although not connected DBI would still warn about rolling back at disconnect
  $schema->txn_rollback;
  $schema->txn_rollback;
}

# make sure AutoCommit => 0 on external handles behaves correctly with scope_guard
warnings_are {
  my $factory = DBICTest->init_schema (AutoCommit => 0);
  cmp_ok ($factory->resultset('CD')->count, '>', 0, 'Something to delete');
  my $dbh = $factory->storage->dbh;

  ok (!$dbh->{AutoCommit}, 'AutoCommit is off on $dbh');
  my $schema = DBICTest::Schema->connect (sub { $dbh });

  lives_ok ( sub {
    my $guard = $schema->txn_scope_guard;
    $schema->resultset('CD')->delete;
    $guard->commit;
  }, 'No attempt to start a transaction with scope guard');

  is ($schema->resultset('CD')->count, 0, 'Deletion successful in txn');

  # this will commit the implicitly started txn
  $dbh->commit;

} [], 'No warnings on AutoCommit => 0 with txn_guard';

# make sure AutoCommit => 0 on external handles behaves correctly with txn_do
warnings_are {
  my $factory = DBICTest->init_schema (AutoCommit => 0);
  cmp_ok ($factory->resultset('CD')->count, '>', 0, 'Something to delete');
  my $dbh = $factory->storage->dbh;

  ok (!$dbh->{AutoCommit}, 'AutoCommit is off on $dbh');
  my $schema = DBICTest::Schema->connect (sub { $dbh });


  lives_ok ( sub {
    $schema->txn_do (sub { $schema->resultset ('CD')->delete });
  }, 'No attempt to start a atransaction with txn_do');

  is ($schema->resultset('CD')->count, 0, 'Deletion successful');

  # this will commit the implicitly started txn
  $dbh->commit;

} [], 'No warnings on AutoCommit => 0 with txn_do';

done_testing;

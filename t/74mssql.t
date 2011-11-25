use strict;
use warnings;

# use this if you keep a copy of DBD::Sybase linked to FreeTDS somewhere else
BEGIN {
  if (my $lib_dirs = $ENV{DBICTEST_MSSQL_PERL5LIB}) {
    unshift @INC, $_ for split /:/, $lib_dirs;
  }
}

use Test::More;
use Test::Exception;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn);


plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_mssql_sybase')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_mssql_sybase');

{
  my $srv_ver = DBICTest::Schema->connect($dsn, $user, $pass)->storage->_server_info->{dbms_version};
  ok ($srv_ver, 'Got a test server version on fresh schema: ' . ($srv_ver||'???') );
}

my $schema;

my $testdb_supports_placeholders = DBICTest::Schema->connect($dsn, $user, $pass)
                                                    ->storage
                                                     ->_supports_typeless_placeholders;
my @test_storages = (
  $testdb_supports_placeholders ? 'DBI::Sybase::Microsoft_SQL_Server' : (),
  'DBI::Sybase::Microsoft_SQL_Server::NoBindVars',
);

for my $storage_type (@test_storages) {
  $schema = DBICTest::Schema->connect($dsn, $user, $pass);

  if ($storage_type =~ /NoBindVars\z/) {
    # since we want to use the nobindvar - disable the capability so the
    # rebless happens to the correct class
    $schema->storage->_use_typeless_placeholders (0);
  }

  local $ENV{DBIC_MSSQL_FREETDS_LOWVER_NOWARN} = 1; # disable nobindvars warning

  $schema->storage->ensure_connected;

  if ($storage_type =~ /NoBindVars\z/) {
    is $schema->storage->disable_sth_caching, 1,
      'prepare_cached disabled for NoBindVars';
  }

  isa_ok($schema->storage, "DBIx::Class::Storage::$storage_type");

  SKIP: {
    skip 'This version of DBD::Sybase segfaults on disconnect', 1 if DBD::Sybase->VERSION < 1.08;

    # start disconnected to test _ping
    $schema->storage->_dbh->disconnect;

    lives_ok {
      $schema->storage->dbh_do(sub { $_[1]->do('select 1') })
    } '_ping works';
  }

  my $dbh = $schema->storage->dbh;

  $dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL
      DROP TABLE artist");
  $dbh->do("IF OBJECT_ID('cd', 'U') IS NOT NULL
      DROP TABLE cd");

  $dbh->do("CREATE TABLE artist (artistid INT IDENTITY PRIMARY KEY, name VARCHAR(100), rank INT DEFAULT '13', charfield CHAR(10) NULL);");
  $dbh->do("CREATE TABLE cd (cdid INT IDENTITY PRIMARY KEY, artist INT,  title VARCHAR(100), year VARCHAR(100), genreid INT NULL, single_track INT NULL);");
# Just to test compat shim, Auto is in Core
  $schema->class('Artist')->load_components('PK::Auto::MSSQL');

# Test PK
  my $new = $schema->resultset('Artist')->create( { name => 'foo' } );
  ok($new->artistid, "Auto-PK worked");

# Test LIMIT
  for (1..6) {
      $schema->resultset('Artist')->create( { name => 'Artist ' . $_, rank => $_ } );
  }

  my $it = $schema->resultset('Artist')->search( { },
      { rows     => 3,
        offset   => 2,
        order_by => 'artistid'
      }
  );

# Test ? in data don't get treated as placeholders
  my $cd = $schema->resultset('CD')->create( {
      artist      => 1,
      title       => 'Does this break things?',
      year        => 2007,
  } );
  ok($cd->id, 'Not treating ? in data as placeholders');

  is( $it->count, 3, "LIMIT count ok" );
  ok( $it->next->name, "iterator->next ok" );
  $it->next;
  $it->next;
  is( $it->next, undef, "next past end of resultset ok" );

# test MONEY column support
  $schema->storage->dbh_do (sub {
      my ($storage, $dbh) = @_;
      eval { $dbh->do("DROP TABLE money_test") };
      $dbh->do(<<'SQL');
  CREATE TABLE money_test (
     id INT IDENTITY PRIMARY KEY,
     amount MONEY NULL
  )
SQL
   });

   my $rs = $schema->resultset('Money');

  my $row;
  lives_ok {
    $row = $rs->create({ amount => 100 });
  } 'inserted a money value';

  cmp_ok $rs->find($row->id)->amount, '==', 100, 'money value round-trip';

  lives_ok {
    $row->update({ amount => 200 });
  } 'updated a money value';

  cmp_ok $rs->find($row->id)->amount, '==', 200,
    'updated money value round-trip';

  lives_ok {
    $row->update({ amount => undef });
  } 'updated a money value to NULL';

  is $rs->find($row->id)->amount,
    undef, 'updated money value to NULL round-trip';

  $rs->delete;

  # test simple transaction with commit
  lives_ok {
    $schema->txn_do(sub {
      $rs->create({ amount => 300 });
    });
  } 'simple transaction';

  cmp_ok $rs->first->amount, '==', 300, 'committed';

  $rs->reset;
  $rs->delete;

  # test rollback
  throws_ok {
    $schema->txn_do(sub {
      $rs->create({ amount => 700 });
      die 'mtfnpy';
    });
  } qr/mtfnpy/, 'simple failed txn';

  is $rs->first, undef, 'rolled back';

  $rs->reset;
  $rs->delete;

  # test multiple active statements
  {
    $rs->create({ amount => 800 + $_ }) for 1..3;

    my @map = (
      [ 'Artist 1', '801.00' ],
      [ 'Artist 2', '802.00' ],
      [ 'Artist 3', '803.00' ]
    );

    my $artist_rs = $schema->resultset('Artist')->search({
      name => { -like => 'Artist %' }
    });;

    my $i = 0;

    while (my $money_row = $rs->next) {
      my $artist_row = $artist_rs->next;

      is_deeply [ $artist_row->name, $money_row->amount ], $map[$i++],
        'multiple active statements';
    }
    $rs->reset;
    $rs->delete;
  }

  # test transaction handling on a disconnected handle
  my $wrappers = {
    no_transaction => sub { shift->() },
    txn_do => sub { my $code = shift; $schema->txn_do(sub { $code->() } ) },
    txn_begin => sub { $schema->txn_begin; shift->(); $schema->txn_commit },
    txn_guard => sub { my $g = $schema->txn_scope_guard; shift->(); $g->commit },
  };
  for my $wrapper (keys %$wrappers) {
    $rs->delete;

    # a reconnect should trigger on next action
    $schema->storage->_get_dbh->disconnect;

    lives_and {
      $wrappers->{$wrapper}->( sub {
        $rs->create({ amount => 900 + $_ }) for 1..3;
      });
      is $rs->count, 3;
    } "transaction on disconnected handle with $wrapper wrapper";
  }

  TODO: {
    local $TODO = 'Transaction handling with multiple active statements will '
                 .'need eager cursor support.';

    # test transaction handling on a disconnected handle with multiple active
    # statements
    my $wrappers = {
      no_transaction => sub { shift->() },
      txn_do => sub { my $code = shift; $schema->txn_do(sub { $code->() } ) },
      txn_begin => sub { $schema->txn_begin; shift->(); $schema->txn_commit },
      txn_guard => sub { my $g = $schema->txn_scope_guard; shift->(); $g->commit },
    };
    for my $wrapper (keys %$wrappers) {
      $rs->reset;
      $rs->delete;
      $rs->create({ amount => 1000 + $_ }) for (1..3);

      my $artist_rs = $schema->resultset('Artist')->search({
        name => { -like => 'Artist %' }
      });;

      $rs->next;

      my $map = [ ['Artist 1', '1002.00'], ['Artist 2', '1003.00'] ];

      lives_and {
        my @results;

        $wrappers->{$wrapper}->( sub {
          while (my $money = $rs->next) {
            my $artist = $artist_rs->next;
            push @results, [ $artist->name, $money->amount ];
          };
        });

        is_deeply \@results, $map;
      } "transactions with multiple active statement with $wrapper wrapper";
    }
  }

  # test RNO detection when version detection fails
  SKIP: {
    my $storage = $schema->storage;
    my $version = $storage->_server_info->{normalized_dbms_version};

    skip 'could not detect SQL Server version', 1 if not defined $version;

    my $have_rno = $version >= 9 ? 1 : 0;

    local $storage->{_dbh_details}{info} = {}; # delete cache

    my $rno_detected =
      ($storage->sql_limit_dialect eq 'RowNumberOver') ? 1 : 0;

    ok (($have_rno == $rno_detected),
      'row_number() over support detected correctly');
  }

  {
    my $schema = DBICTest::Schema->clone;
    $schema->connection($dsn, $user, $pass);

    like $schema->storage->sql_maker->{limit_dialect},
      qr/^(?:Top|RowNumberOver)\z/,
      'sql_maker is correct on unconnected schema';
  }
}

# test op-induced autoconnect
lives_ok (sub {

  my $schema =  DBICTest::Schema->clone;
  $schema->connection($dsn, $user, $pass);

  my $artist = $schema->resultset ('Artist')->search ({}, { order_by => 'artistid' })->next;
  is ($artist->id, 1, 'Artist retrieved successfully');
}, 'Query-induced autoconnect works');

# test AutoCommit=0
{
  local $ENV{DBIC_UNSAFE_AUTOCOMMIT_OK} = 1;
  my $schema2 = DBICTest::Schema->connect($dsn, $user, $pass, { AutoCommit => 0 });

  my $rs = $schema2->resultset('Money');

  $rs->delete;
  $schema2->txn_commit;

  is $rs->count, 0, 'initially empty'
    || diag ('Found row with amount ' . $_->amount) for $rs->all;

  $rs->create({ amount => 3000 });
  $schema2->txn_rollback;

  is $rs->count, 0, 'rolled back in AutoCommit=0'
    || diag ('Found row with amount ' . $_->amount) for $rs->all;

  $rs->create({ amount => 4000 });
  $schema2->txn_commit;

  cmp_ok $rs->first->amount, '==', 4000, 'committed in AutoCommit=0';
}

done_testing;

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->dbh }) {
    $dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL DROP TABLE artist");
    $dbh->do("IF OBJECT_ID('cd', 'U') IS NOT NULL DROP TABLE cd");
    $dbh->do("IF OBJECT_ID('money_test', 'U') IS NOT NULL DROP TABLE money_test");
  }
}

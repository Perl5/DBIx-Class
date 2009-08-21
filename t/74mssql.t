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
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn);

my $TESTS = 13;

plan tests => $TESTS * 2;

my @storage_types = (
  'DBI::Sybase::Microsoft_SQL_Server',
  'DBI::Sybase::Microsoft_SQL_Server::NoBindVars',
);
my $storage_idx = -1;
my $schema;

for my $storage_type (@storage_types) {
  $storage_idx++;

  $schema = DBICTest::Schema->clone;

  if ($storage_idx != 0) { # autodetect
    $schema->storage_type("::$storage_type");
  }

  $schema->connection($dsn, $user, $pass);

  $schema->storage->ensure_connected;

  if ($storage_idx == 0 && ref($schema->storage) =~ /NoBindVars\z/) {
    my $tb = Test::More->builder;
    $tb->skip('no placeholders') for 1..$TESTS;
    next;
  }

  isa_ok($schema->storage, "DBIx::Class::Storage::$storage_type");

# start disconnected to test reconnection
  $schema->storage->_dbh->disconnect;

  my $dbh;
  lives_ok (sub {
    $dbh = $schema->storage->dbh;
  }, 'reconnect works');

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
}

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->dbh }) {
    $dbh->do("IF OBJECT_ID('artist', 'U') IS NOT NULL DROP TABLE artist");
    $dbh->do("IF OBJECT_ID('cd', 'U') IS NOT NULL DROP TABLE cd");
    $dbh->do("IF OBJECT_ID('money_test', 'U') IS NOT NULL DROP TABLE money_test");
  }
}

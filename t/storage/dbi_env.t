use strict;
use warnings;
use lib qw(t/lib);
use DBICTest;
use Test::More;
use Test::Exception;
use DBIx::Class::_Util 'sigwarn_silencer';

BEGIN { delete @ENV{qw(DBI_DSN DBI_DRIVER)} }

$ENV{DBICTEST_LOCK_HOLDER} = -1;

# pre-populate
my $schema = DBICTest->init_schema(sqlite_use_file => 1);

my $dbname = DBICTest->_sqlite_dbname(sqlite_use_file => 1);

sub count_sheep {
    my $schema = shift;

    local $SIG{__WARN__} = sigwarn_silencer(
      qr/
        \QThis version of DBIC does not yet seem to supply a driver for your particular RDBMS\E
          |
        \QUnable to extract a driver name from connect info\E
          |
        \QYour storage class (DBIx::Class::Storage::DBI) does not set sql_limit_dialect\E
      /x
    );

    scalar $schema->resultset('Artist')->search( { name => "Exploding Sheep" } )
        ->all;
}

$schema = DBICTest::Schema->connect("dbi::$dbname");
throws_ok { count_sheep($schema) } qr{I can't work out what driver to use},
    'Driver in DSN empty';
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI';

$schema = DBICTest::Schema->connect("dbi:Test_NonExistant_DBD:$dbname");
throws_ok { count_sheep($schema) }
    qr{Can't locate DBD/Test_NonExistant_DBD\.pm in \@INC},
    "Driver class doesn't exist";
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI';

$ENV{DBI_DSN} = "dbi::$dbname";
$schema = DBICTest::Schema->connect;
throws_ok { count_sheep($schema) } qr{I can't work out what driver to use},
    "Driver class not defined in DBI_DSN either.";
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI';

$ENV{DBI_DSN} = "dbi:Test_NonExistant_DBD2:$dbname";
$schema = DBICTest::Schema->connect;
throws_ok { count_sheep($schema) }
    qr{Can't locate DBD/Test_NonExistant_DBD2\.pm in \@INC},
    "Driver class defined in DBI_DSN doesn't exist";
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI';

$ENV{DBI_DSN} = "dbi::$dbname";
$ENV{DBI_DRIVER} = 'Test_NonExistant_DBD3';
$schema = DBICTest::Schema->connect;
throws_ok { count_sheep($schema) }
    qr{Can't locate DBD/Test_NonExistant_DBD3\.pm in \@INC},
    "Driver class defined in DBI_DRIVER doesn't exist";
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI';

$ENV{DBI_DSN} = "dbi:Test_NonExistant_DBD4:$dbname";
$schema = DBICTest::Schema->connect;
throws_ok { count_sheep($schema) }
qr{Can't locate DBD/Test_NonExistant_DBD4\.pm in \@INC},
    "Driver class defined in DBI_DSN doesn't exist";
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI';

delete @ENV{qw(DBI_DSN DBI_DRIVER)};

$schema = DBICTest::Schema->connect("dbi:SQLite:$dbname");
lives_ok { count_sheep($schema) } 'SQLite passed to connect_info';
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI::SQLite';

$ENV{DBI_DRIVER} = 'SQLite';
$schema = DBICTest::Schema->connect("dbi::$dbname");
lives_ok { count_sheep($schema) } 'SQLite in DBI_DRIVER';
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI::SQLite';

delete $ENV{DBI_DRIVER};
$ENV{DBI_DSN} = "dbi:SQLite:$dbname";
$schema = DBICTest::Schema->connect;
lives_ok { count_sheep($schema) } 'SQLite in DBI_DSN';
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI::SQLite';

$ENV{DBI_DRIVER} = 'SQLite';
$schema = DBICTest::Schema->connect;
lives_ok { count_sheep($schema) } 'SQLite in DBI_DSN (and DBI_DRIVER)';
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI::SQLite';

$ENV{DBI_DSN} = "dbi::$dbname";
$ENV{DBI_DRIVER} = 'SQLite';
$schema = DBICTest::Schema->connect;
lives_ok { count_sheep($schema) } 'SQLite in DBI_DRIVER (not DBI_DSN)';
isa_ok $schema->storage, 'DBIx::Class::Storage::DBI::SQLite';

# make sure that dynamically setting DBI_DSN post-connect works
{
  local $ENV{DBI_DSN};

  my $s = DBICTest::Schema->connect();

  throws_ok {
    $s->storage->ensure_connected
  } qr/You did not provide any connection_info/,
  'sensible exception on empty conninfo connect';

  $ENV{DBI_DSN} = 'dbi:SQLite::memory:';

  lives_ok { $s->storage->ensure_connected } 'Second connection attempt worked';
  isa_ok ( $s->storage, 'DBIx::Class::Storage::DBI::SQLite' );
}

done_testing;

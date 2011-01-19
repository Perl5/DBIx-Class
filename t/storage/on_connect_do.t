use strict;
use warnings;

# !!! do not replace this with done_testing - tests reside in the callbacks
# !!! number of calls is important
use Test::More tests => 13;
# !!!
use Test::Warn;
use Test::Exception;

use lib qw(t/lib);
use base 'DBICTest';
require DBI;


my $schema = DBICTest->init_schema(
    no_connect  => 1,
    no_deploy   => 1,
);

ok $schema->connection(
  DBICTest->_database,
  {
    on_connect_do => 'CREATE TABLE TEST_empty (id INTEGER)',
  },
), 'connection()';

is_deeply (
  $schema->storage->dbh->selectall_arrayref('SELECT * FROM TEST_empty'),
  [],
  'string version on_connect_do() worked'
);

$schema->storage->disconnect;

ok $schema->connection(
    sub { DBI->connect(DBICTest->_database, undef, undef, { AutoCommit => 0 }) },
    {
        on_connect_do       => [
            'CREATE TABLE TEST_empty (id INTEGER)',
            [ 'INSERT INTO TEST_empty VALUES (?)', {}, 2 ],
            \&insert_from_subref,
        ],
        on_disconnect_do    =>
            [\&check_exists, 'DROP TABLE TEST_empty', \&check_dropped],
    },
), 'connection()';

warnings_exist {
  $schema->storage->ensure_connected
} qr/The 'RaiseError' of the externally supplied DBI handle is set to false/,
'Warning on clobbered AutoCommit => 0 fired';

is_deeply (
  $schema->storage->dbh->selectall_arrayref('SELECT * FROM TEST_empty'),
  [ [ 2 ], [ 3 ], [ 7 ] ],
  'on_connect_do() worked'
);
dies_ok {
  $schema->storage->dbh->do('SELECT 1 FROM TEST_nonexistent');
} 'Searching for nonexistent table dies';

$schema->storage->disconnect();

my($connected, $disconnected, @cb_args);
ok $schema->connection(
    DBICTest->_database,
    {
        on_connect_do       => sub { $connected = 1; @cb_args = @_; },
        on_disconnect_do    => sub { $disconnected = 1 },
    },
), 'second connection()';
$schema->storage->dbh->do('SELECT 1');
ok $connected, 'on_connect_do() called after connect()';
ok ! $disconnected, 'on_disconnect_do() not called after connect()';
$schema->storage->disconnect();
ok $disconnected, 'on_disconnect_do() called after disconnect()';

isa_ok($cb_args[0], 'DBIx::Class::Storage', 'first arg to on_connect_do hook');

sub check_exists {
    my $storage = shift;
    ok $storage->dbh->do('SELECT 1 FROM TEST_empty'), 'Table still exists';
    return;
}

sub check_dropped {
    my $storage = shift;

    dies_ok {
      $storage->dbh->do('SELECT 1 FROM TEST_empty');
    } 'Reading from dropped table fails';
    return;
}

sub insert_from_subref {
    my $storage = shift;
    return [
        [ 'INSERT INTO TEST_empty VALUES (?)', {}, 3 ],
        'INSERT INTO TEST_empty VALUES (7)',
    ];
}

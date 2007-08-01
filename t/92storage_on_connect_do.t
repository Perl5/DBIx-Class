use strict;
use warnings;

use Test::More tests => 5;

use lib qw(t/lib);
use base 'DBICTest';


my $schema = DBICTest->init_schema(
    no_connect  => 1,
    no_deploy   => 1,
);
ok $schema->connection(
    DBICTest->_database,
    {
        on_connect_do       => ['CREATE TABLE TEST_empty (id INTEGER)'],
        on_disconnect_do    =>
            [\&check_exists, 'DROP TABLE TEST_empty', \&check_dropped],
    },
), 'connection()';

ok $schema->storage->dbh->do('SELECT 1 FROM TEST_empty'), 'on_connect_do() worked';
eval { $schema->storage->dbh->do('SELECT 1 FROM TEST_nonexistent'); };
ok $@, 'Searching for nonexistent table dies';

$schema->storage->disconnect();

sub check_exists {
    my $storage = shift;
    ok $storage->dbh->do('SELECT 1 FROM TEST_empty'), 'Table still exists';
}

sub check_dropped {
    my $storage = shift;
    eval { $storage->dbh->do('SELECT 1 FROM TEST_empty'); };
    ok $@, 'Reading from dropped table fails';
}

use strict;
use warnings;
no warnings qw/once redefine/;

use lib qw(t/lib);
use DBICTest;

use Test::More tests => 9;

my $schema = DBICTest->init_schema(
  no_connect  => 1,
  no_deploy   => 1,
);

local *DBIx::Class::Storage::DBI::connect_call_foo = sub {
  isa_ok $_[0], 'DBIx::Class::Storage::DBI',
    'got storage in connect_call method';
  is $_[1], 'bar', 'got param in connect_call method';
};

local *DBIx::Class::Storage::DBI::disconnect_call_foo = sub {
  isa_ok $_[0], 'DBIx::Class::Storage::DBI',
    'got storage in disconnect_call method';
};

ok $schema->connection(
  DBICTest->_database,
  {
    on_connect_call => [
        [ do_sql => 'create table test1 (id integer)' ],
        [ do_sql => [ 'insert into test1 values (?)', {}, 1 ] ],
        [ do_sql => sub { ['insert into test1 values (2)'] } ],
        [ sub { $_[0]->dbh->do($_[1]) }, 'insert into test1 values (3)' ],
        # this invokes $storage->connect_call_foo('bar') (above)
        [ foo => 'bar' ],
    ],
    on_connect_do => 'insert into test1 values (4)',
    on_disconnect_call => 'foo',
  },
), 'connection()';

is_deeply (
  $schema->storage->dbh->selectall_arrayref('select * from test1'),
  [ [ 1 ], [ 2 ], [ 3 ], [ 4 ] ],
  'on_connect_call/do actions worked'
);

local *DBIx::Class::Storage::DBI::connect_call_foo = sub {
  isa_ok $_[0], 'DBIx::Class::Storage::DBI',
    'got storage in connect_call method';
};

local *DBIx::Class::Storage::DBI::connect_call_bar = sub {
  isa_ok $_[0], 'DBIx::Class::Storage::DBI',
    'got storage in connect_call method';
};

$schema->storage->disconnect;

ok $schema->connection(
  DBICTest->_database,
  {
    # method list form
    on_connect_call => [ 'foo', sub { ok 1, "coderef in list form" }, 'bar' ],
  },
), 'connection()';

$schema->storage->ensure_connected;

use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;

my $schema = DBICTest->init_schema( sqlite_use_file => 1 );

is( ref($schema->storage), 'DBIx::Class::Storage::DBI::SQLite',
    'Storage reblessed correctly into DBIx::Class::Storage::DBI::SQLite' );

my $storage = $schema->storage;
$storage->ensure_connected;

throws_ok {
    $schema->storage->throw_exception('test_exception_42');
} qr/\btest_exception_42\b/, 'basic exception';

throws_ok {
    $schema->resultset('CD')->search_literal('broken +%$#$1')->all;
} qr/prepare_cached failed/, 'exception via DBI->HandleError, etc';


# make sure repeated disconnection works
{
  my $fn = DBICTest->_sqlite_dbfilename;

  lives_ok {
    $schema->storage->ensure_connected;
    my $dbh = $schema->storage->dbh;
    $schema->storage->disconnect for 1,2;
    unlink $fn;
    $dbh->disconnect;
  };

  lives_ok {
    $schema->storage->ensure_connected;
    $schema->storage->disconnect for 1,2;
    unlink $fn;
    $schema->storage->disconnect for 1,2;
  };

  lives_ok {
    $schema->storage->ensure_connected;
    $schema->storage->_dbh->disconnect;
    unlink $fn;
    $schema->storage->disconnect for 1,2;
  };
}


# testing various invocations of connect_info ([ ... ])

my $coderef = sub { 42 };
my $invocations = {
  'connect_info ([ $d, $u, $p, \%attr, \%extra_attr])' => {
      args => [
          'foo',
          'bar',
          undef,
          {
            on_connect_do => [qw/a b c/],
            PrintError => 0,
          },
          {
            AutoCommit => 1,
            on_disconnect_do => [qw/d e f/],
          },
          {
            unsafe => 1,
            auto_savepoint => 1,
          },
        ],
      dbi_connect_info => [
          'foo',
          'bar',
          undef,
          {
            %{$storage->_default_dbi_connect_attributes || {} },
            PrintError => 0,
            AutoCommit => 1,
          },
      ],
  },

  'connect_info ([ \%code, \%extra_attr ])' => {
      args => [
          $coderef,
          {
            on_connect_do => [qw/a b c/],
            PrintError => 0,
            AutoCommit => 1,
            on_disconnect_do => [qw/d e f/],
          },
          {
            unsafe => 1,
            auto_savepoint => 1,
          },
        ],
      dbi_connect_info => [
          $coderef,
      ],
  },

  'connect_info ([ \%attr ])' => {
      args => [
          {
            on_connect_do => [qw/a b c/],
            PrintError => 1,
            AutoCommit => 0,
            on_disconnect_do => [qw/d e f/],
            user => 'bar',
            dsn => 'foo',
          },
          {
            unsafe => 1,
            auto_savepoint => 1,
          },
      ],
      dbi_connect_info => [
          'foo',
          'bar',
          undef,
          {
            %{$storage->_default_dbi_connect_attributes || {} },
            PrintError => 1,
            AutoCommit => 0,
          },
      ],
      warn => qr/\QYou provided explicit AutoCommit => 0 in your connection_info/,
  },
  'connect_info ([ \%attr_with_coderef ])' => {
      args => [ {
        dbh_maker => $coderef,
        dsn => 'blah',
        user => 'bleh',
        on_connect_do => [qw/a b c/],
        on_disconnect_do => [qw/d e f/],
      } ],
      dbi_connect_info => [
        $coderef
      ],
      warn => qr/Attribute\(s\) 'dsn', 'user' in connect_info were ignored/,
  },
};

for my $type (keys %$invocations) {
  local $ENV{DBIC_UNSAFE_AUTOCOMMIT_OK};

  # we can not use a cloner portably because of the coderef
  # so compare dumps instead
  local $Data::Dumper::Sortkeys = 1;
  my $arg_dump = Dumper ($invocations->{$type}{args});

  warnings_exist (
    sub { $storage->connect_info ($invocations->{$type}{args}) },
     $invocations->{$type}{warn} || [],
    'Warned about ignored attributes',
  );

  is ($arg_dump, Dumper ($invocations->{$type}{args}), "$type didn't modify passed arguments");

  is_deeply ($storage->_dbi_connect_info, $invocations->{$type}{dbi_connect_info}, "$type produced correct _dbi_connect_info");
  ok ( (not $storage->auto_savepoint and not $storage->unsafe), "$type correctly ignored extra hashref");

  is_deeply (
    [$storage->on_connect_do, $storage->on_disconnect_do ],
    [ [qw/a b c/], [qw/d e f/] ],
    "$type correctly parsed DBIC specific on_[dis]connect_do",
  );
}

# make sure connection-less storages do not throw on _determine_driver
# but work with ENV at the same time
SKIP: for my $env_dsn (undef, (DBICTest->_database)[0] ) {
  skip( 'Subtest relies on being connected to SQLite without overrides', 1 ) if (
    $ENV{DBICTEST_SWAPOUT_SQLAC_WITH}
      or
    ( $env_dsn and $env_dsn !~ /\:SQLite\:/ )
  );

  local $ENV{DBI_DSN} = $env_dsn || '';

  my $s = DBICTest::Schema->connect();
  is_deeply (
    $s->storage->connect_info,
    [],
    'Starting with no explicitly passed in connect info'
  . ($env_dsn ? ' (with DBI_DSN)' : ''),
  );

  my $sm = $s->storage->sql_maker;

  ok (! $s->storage->connected, 'Storage does not appear connected after SQLMaker instance is taken');

  if ($env_dsn) {
    isa_ok($sm, 'DBIx::Class::SQLMaker');

    ok ( $s->storage->_driver_determined, 'Driver determined (with DBI_DSN)');
    isa_ok ( $s->storage, 'DBIx::Class::Storage::DBI::SQLite' );
  }
  else {
    isa_ok($sm, 'DBIx::Class::SQLMaker');

    ok (! $s->storage->_driver_determined, 'Driver undetermined');

    throws_ok {
      $s->storage->ensure_connected
    } qr/You did not provide any connection_info/,
    'sensible exception on empty conninfo connect';
  }
}

done_testing;

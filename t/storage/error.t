use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

for my $conn_args (
  [ on_connect_do   => "_NOPE_" ],
  [ on_connect_call => sub { shift->_dbh->do("_NOPE_") } ],
  [ on_connect_call => "_NOPE_" ],
) {
  for my $method (qw( ensure_connected _server_info _get_server_version _get_dbh )) {

    my $s = DBICTest->init_schema(
      no_deploy => 1,
      on_disconnect_call => sub { fail 'Disconnector should not be invoked' },
      @$conn_args
    );

    my $storage = $s->storage;
    $storage = $storage->master
      if $storage->isa('DBIx::Class::Storage::DBI::Replicated');

    ok( ! $storage->connected, 'Starting unconnected' );

    my $desc = "calling $method with broken on_connect action @{[ explain $conn_args ]}";

    throws_ok { $storage->$method }
      qr/ _NOPE_ \b/x,
      "Throwing correctly when $desc";

    ok( ! $storage->connected, "Still not connected after $desc" );

    # this checks that the on_disconect_call FAIL won't trigger
    $storage->disconnect;
  }
}

for my $conn_args (
  [ on_disconnect_do   => "_NOPE_" ],
  [ on_disconnect_call => sub { shift->_dbh->do("_NOPE_") } ],
  [ on_disconnect_call => "_NOPE_" ],
) {
  my $s = DBICTest->init_schema( no_deploy => 1, @$conn_args );

  my $storage = $s->storage;
  $storage = $storage->master
    if $storage->isa('DBIx::Class::Storage::DBI::Replicated');

  my $desc = "broken on_disconnect action @{[ explain $conn_args ]}";

  # connect + ping
  my $dbh = $storage->dbh;

  ok ($dbh->FETCH('Active'), 'Freshly connected DBI handle is healthy');

  warnings_exist { eval { $storage->disconnect } } [
    qr/\QDisconnect action failed\E .+ _NOPE_ \b/x
  ], "Found warning of failed $desc";

  ok (! $dbh->FETCH('Active'), "Actual DBI disconnect was not prevented by $desc" );
}

my $schema = DBICTest->init_schema;

warnings_are ( sub {
  throws_ok (
    sub {
      $schema->resultset('CD')->create({ title => 'vacation in antarctica' })
    },
    qr/DBI Exception.+(?x:
      \QNOT NULL constraint failed: cd.artist\E
        |
      \Qcd.artist may not be NULL\E
    )/s
  );  # as opposed to some other error
}, [], 'No warnings besides exception' );

my $dbh = $schema->storage->dbh;

throws_ok (
  sub {
    $dbh->do ('INSERT INTO nonexistent_table VALUES (1)')
  },
  qr/DBI Exception.+no such table.+nonexistent_table/s,
  'DBI exceptions properly handled by dbic-installed callback'
);

# This usage is a bit unusual but it was actually seen in the wild
# destruction of everything except the $dbh should use the proper
# exception fallback:

SKIP: {
  if ( !!DBIx::Class::_ENV_::PEEPEENESS ) {
    skip "Your perl version $] appears to leak like a sieve - skipping garbage collected \$schema test", 1;
  }

  undef ($schema);
  throws_ok (
    sub {
      $dbh->do ('INSERT INTO nonexistent_table VALUES (1)')
    },
    qr/DBI Exception.+unhandled by DBIC.+no such table.+nonexistent_table/s,
    'callback works after $schema is gone'
  );
}

done_testing;

BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;

# so we can see the retry exceptions (if any)
BEGIN { $ENV{DBIC_STORAGE_RETRY_DEBUG} = 1 }

use DBIx::Class::Optional::Dependencies ();


use DBICTest;

for my $type (qw/PG MYSQL SQLite/) {

  SKIP: {

    DBIx::Class::Optional::Dependencies->skip_without( 'test_rdbms_' . lc $type );

    my @dsn = $type eq 'SQLite'
      ? ( DBICTest->_database(sqlite_use_file => 1) )
      : ( @ENV{map { "DBICTEST_${type}_${_}" } qw/DSN USER PASS/} )
    ;

    my $schema = DBICTest::Schema->connect (@dsn);

    # emulate a singleton-factory, just cache the object *somewhere in a different package*
    # to induce out-of-order destruction
    $DBICTest::FakeSchemaFactory::schema = $schema;

    ok (!$schema->storage->connected, "$type: start disconnected");

    $schema->txn_do (sub {

      ok ($schema->storage->connected, "$type: transaction starts connected");

      my $pid = fork();
      SKIP: {
        skip "Fork failed: $!", 1 if (! defined $pid);

        if ($pid) {
          note "Parent $$ sleeping...";
          wait();
          note "Parent $$ woken up after child $pid exit";
        }
        else {
          note "Child $$ terminating";
          undef $DBICTest::FakeSchemaFactory::schema;
          exit 0;
        }

        ok ($schema->storage->connected, "$type: parent still connected (in txn_do)");
      }
    });

    ok ($schema->storage->connected, "$type: parent still connected (outside of txn_do)");

    undef $DBICTest::FakeSchemaFactory::schema;
  }
}

done_testing;

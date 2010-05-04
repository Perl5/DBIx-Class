use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

for my $type (qw/PG MYSQL/) {

  SKIP: {
    skip "Skipping $type tests without DBICTEST_${type}_DSN", 1
      unless $ENV{"DBICTEST_${type}_DSN"};

    my $schema = DBICTest::Schema->connect (@ENV{map { "DBICTEST_${type}_${_}" } qw/DSN USER PASS/});

    # emulate a singleton-factory, just cache the object *somewhere in a different package*
    # to induce out-of-order destruction
    $DBICTest::FakeSchemaFactory::schema = $schema;

    # so we can see the retry exceptions (if any)
    $ENV{DBIC_DBIRETRY_DEBUG} = 1;

    ok (!$schema->storage->connected, "$type: start disconnected");

    lives_ok (sub {
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
            exit 0;
          }

          ok ($schema->storage->connected, "$type: parent still connected (in txn_do)");
        }
      });
    });

    ok ($schema->storage->connected, "$type: parent still connected (outside of txn_do)");

    undef $DBICTest::FakeSchemaFactory::schema;
  }
}

done_testing;

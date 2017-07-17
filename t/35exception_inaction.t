BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;


use DBICTest::RunMode;
BEGIN {
  if( DBICTest::RunMode->is_plain ) {
    print "1..0 # SKIP not running dangerous segfault-prone test on plain install\n";
    exit 0;
  }
}

use DBICTest::Util 'capture_stderr';
use DBIx::Class::Schema;

# Do not use T::B - the test is hard enough not to segfault as it is
my $test_count = 0;

# start with one failure, and decrement it at the end
my $failed = 1;

sub ok {
  printf STDOUT ("%s %u - %s\n",
    ( $_[0] ? 'ok' : 'not ok' ),
    ++$test_count,
    $_[1] || '',
  );

  unless( $_[0] ) {
    $failed++;
    printf STDERR ("# Failed test #%d at %s line %d\n",
      $test_count,
      (caller(0))[1,2]
    );
  }

  return !!$_[0];
}

# this is incredibly horrible...
# demonstrate utter breakage of the reconnection/retry logic
#
my $output = capture_stderr {
ESCAPE:
{
  # yes, make it even dirtier
  my $schema = 'DBIx::Class::Schema';

  $schema->connection('dbi:SQLite::memory:');
  $schema->storage->ensure_connected;
  $schema->storage->_dbh->disconnect;

  # silences "exitting sub via last"
  local $SIG{__WARN__} = sub {};

  $schema->exception_action(sub {
    ok(1, 'exception_action invoked');
    # essentially what Dancer2's redirect() does after https://github.com/PerlDancer/Dancer2/pull/485
    # which "nicely" combines with: https://metacpan.org/source/MARKOV/Log-Report-1.12/lib/Dancer2/Plugin/LogReport.pm#L143
    # as encouraged by: https://metacpan.org/pod/release/MARKOV/Log-Report-1.12/lib/Dancer2/Plugin/LogReport.pod#Logging-DBIC-database-queries-and-errors
    last ESCAPE;
  });

  # this *DOES* throw, but the exception will *NEVER SHOW UP*
  $schema->storage->dbh_do(sub { $_[1]->selectall_arrayref("SELECT * FROM wfwqfdqefqef") } );

  # NEITHER will this
  ok(0, "Nope");
}};

ok(1, "Post-escape reached");

ok(
  !!( $output =~ /DBIx::Class INTERNAL PANIC.+FIX YOUR ERROR HANDLING/s ),
  'Proper warning emitted on STDERR'
) or print STDERR "Instead found:\n\n$output\n";

print "1..$test_count\n";

# this is our "done_testing"
$failed--;

# avoid tasty segfaults on 5.8.x
exit( $failed );

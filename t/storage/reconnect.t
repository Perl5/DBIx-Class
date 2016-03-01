BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use B::Deparse;
use Scalar::Util 'weaken';
use Test::More;
use Test::Exception;

use DBICTest;

my $db_orig = DBICTest->_sqlite_dbfilename;
my $db_tmp  = "$db_orig.tmp";

# Set up the "usual" sqlite for DBICTest
my $schema = DBICTest->init_schema( sqlite_use_file => 1 );

my $exception_action_count;
$schema->exception_action(sub {
  $exception_action_count++;
  die @_;
});

# Make sure we're connected by doing something
my @art = $schema->resultset("Artist")->search({ }, { order_by => { -desc => 'name' }});
cmp_ok(@art, '==', 3, "Three artists returned");

# Disconnect the dbh, and be sneaky about it
# Also test if DBD::SQLite finaly knows how to ->disconnect properly
{
  my $w;
  local $SIG{__WARN__} = sub { $w = shift };
  $schema->storage->_dbh->disconnect;
  ok ($w !~ /active statement handles/, 'SQLite can disconnect properly');
}

# Try the operation again - What should happen here is:
#   1. S::DBI blindly attempts the SELECT, which throws an exception
#   2. It catches the exception, checks ->{Active}/->ping, sees the disconnected state...
#   3. Reconnects, and retries the operation
#   4. Success!
my @art_two = $schema->resultset("Artist")->search({ }, { order_by => { -desc => 'name' }});
cmp_ok(@art_two, '==', 3, "Three artists returned");

### Now, disconnect the dbh, and move the db file;
# create a new one full of garbage, prevent SQLite from connecting.
$schema->storage->_dbh->disconnect;
rename( $db_orig, $db_tmp )
  or die "failed to move $db_orig to $db_tmp: $!";
open my $db_file, '>', $db_orig;
print $db_file 'THIS IS NOT A REAL DATABASE';
close $db_file;

### Try the operation again... it should fail, since there's no valid db
{
  # Catch the DBI connection error
  local $SIG{__WARN__} = sub {};
  throws_ok {
    $schema->resultset("Artist")->create({ name => 'not gonna happen' });
  }  qr/not a database/, 'The operation failed';
}

ok (! $schema->storage->connected, 'We are not connected' );

### Now, move the db file back to the correct name
unlink($db_orig) or die "could not delete $db_orig: $!";
rename( $db_tmp, $db_orig )
  or die "could not move $db_tmp to $db_orig: $!";

### Try the operation again... this time, it should succeed
my @art_four;
lives_ok {
    @art_four = $schema->resultset("Artist")->search( {}, { order_by => { -desc => 'name' } } );
} 'The operation succeeded';
cmp_ok( @art_four, '==', 3, "Three artists returned" );

# check that reconnection contexts are preserved in txn_do / dbh_do

my $args = [1, 2, 3];

my $ctx_map = {
  VOID => {
    invoke => sub { shift->(); 1 },
    wa => undef,
  },
  SCALAR => {
    invoke => sub { my $foo = shift->() },
    wa => '',
  },
  LIST => {
    invoke => sub { my @foo = shift->() },
    wa => 1,
  },
};

for my $ctx (keys %$ctx_map) {

  # start disconnected and then connected
  $schema->storage->disconnect;
  $exception_action_count = 0;

  for (1, 2) {
    my $disarmed;

    $ctx_map->{$ctx}{invoke}->(sub { $schema->txn_do(sub {
      is_deeply (\@_, $args, 'Args propagated correctly' );

      is (wantarray(), $ctx_map->{$ctx}{wa}, "Correct $ctx context");

      # this will cause a retry
      $schema->storage->_dbh->disconnect unless $disarmed++;

      isa_ok ($schema->resultset('Artist')->next, 'DBICTest::Artist');
    }, @$args) });
  }

  is( $exception_action_count, 0, 'exception_action never called' );
};

# make sure RT#110429 does not recur on manual DBI-side disconnect
for my $cref (
  sub {
    my $schema = shift;

    my $g = $schema->txn_scope_guard;

    is( $schema->storage->transaction_depth, 1, "Expected txn depth" );

    $schema->storage->_dbh->disconnect;

    $schema->storage->dbh_do(sub { $_[1]->do('SELECT 1') } );
  },
  sub {
    my $schema = shift;
    $schema->txn_do(sub {
      $schema->storage->_dbh->disconnect
    } );
  },
  sub {
    my $schema = shift;
    $schema->txn_do(sub {
      $schema->storage->disconnect;
      die "VIOLENCE";
    } );
  },
) {

  note( "Testing with " . B::Deparse->new->coderef2text($cref) );

  $schema->storage->disconnect;
  $exception_action_count = 0;

  ok( !$schema->storage->connected, 'Not connected' );

  is( $schema->storage->transaction_depth, undef, "Start with unknown txn depth" );

  # messages vary depending on version and whether txn or do, whatever
  dies_ok {
    $cref->($schema)
  } 'Threw *something*';

  ok( !$schema->storage->connected, 'Not connected as a result of failed rollback' );

  is( $schema->storage->transaction_depth, undef, "Depth expectedly unknown after failed rollbacks" );

  is( $exception_action_count, 1, "exception_action called only once" );
}

# check exception_action under tenacious disconnect
{
  $schema->storage->disconnect;
  $exception_action_count = 0;

  throws_ok { $schema->txn_do(sub {
    $schema->storage->_dbh->disconnect;

    $schema->resultset('Artist')->next;
  })} qr/prepare on inactive database handle/;

  is( $exception_action_count, 1, "exception_action called only once" );
}

# check that things aren't crazy with a non-violent disconnect
{
  my $schema = DBICTest->init_schema( sqlite_use_file => 0, no_deploy => 1 );
  weaken( my $ws = $schema );

  $schema->is_executed_sql_bind( sub {
    $ws->txn_do(sub { $ws->storage->disconnect } );
  }, [ [ 'BEGIN' ] ], 'Only one BEGIN statement' );

  $schema->is_executed_sql_bind( sub {
    my $g = $ws->txn_scope_guard;
    $ws->storage->disconnect;
  }, [ [ 'BEGIN' ] ], 'Only one BEGIN statement' );
}

done_testing;

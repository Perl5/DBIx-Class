use strict;
use warnings;

use FindBin;
use File::Copy 'move';
use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $db_orig = DBICTest->_sqlite_dbfilename;
my $db_tmp  = "$db_orig.tmp";

# Set up the "usual" sqlite for DBICTest
my $schema = DBICTest->init_schema( sqlite_use_file => 1 );

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
move( $db_orig, $db_tmp )
  or die "failed to move $db_orig to $db_tmp: $!";
open my $db_file, '>', $db_orig;
print $db_file 'THIS IS NOT A REAL DATABASE';
close $db_file;

### Try the operation again... it should fail, since there's no valid db
{
  # Catch the DBI connection error
  local $SIG{__WARN__} = sub {};
  throws_ok {
    my @art_three = $schema->resultset("Artist")->search( {}, { order_by => { -desc => 'name' } } );
  }  qr/not a database/, 'The operation failed';
}

ok (! $schema->storage->connected, 'We are not connected' );

### Now, move the db file back to the correct name
unlink($db_orig) or die "could not delete $db_orig: $!";
move( $db_tmp, $db_orig )
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
};

done_testing;

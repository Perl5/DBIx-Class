use strict;
use warnings;

use Test::More;

use lib 't/lib';
BEGIN {
  require DBICTest::RunMode;
  plan( skip_all => "Skipping test on plain module install" )
    if DBICTest::RunMode->is_plain;
}

use Test::Exception;
use DBICTest;
use File::Temp ();

plan tests => 2;
my $wait_for = 120;  # how many seconds to wait

# don't lock anything - this is a tempfile anyway
$ENV{DBICTEST_LOCK_HOLDER} = -1;

for my $close (0,1) {

  my $tmp = File::Temp->new(
    UNLINK => 1,
    DIR => 't/var',
    SUFFIX => '.db',
    TEMPLATE => 'DBIxClass-XXXXXX',
    EXLOCK => 0,  # important for BSD and derivatives
  );

  my $tmp_fn = $tmp->filename;
  close $tmp if $close;

  local $SIG{ALRM} = sub { die sprintf (
    "Timeout of %d seconds reached (tempfile still open: %s)",
    $wait_for, $close ? 'No' : 'Yes'
  )};

  alarm $wait_for;

  lives_ok (sub {
    my $schema = DBICTest::Schema->connect ("DBI:SQLite:$tmp_fn");
    $schema->storage->dbh_do(sub { $_[1]->do('PRAGMA synchronous = OFF') });
    DBICTest->deploy_schema ($schema);
    DBICTest->populate_schema ($schema);
  });

  alarm 0;
}

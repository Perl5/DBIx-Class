use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Scope::Guard ();

# XXX we're only testing TIMESTAMP here

my ($dsn, $user, $pass)    = @ENV{map { "DBICTEST_FIREBIRD_${_}" }      qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_FIREBIRD_ODBC_${_}" } qw/DSN USER PASS/};

if (not ($dsn || $dsn2)) {
  plan skip_all => <<'EOF';
Set $ENV{DBICTEST_FIREBIRD_DSN} and/or $ENV{DBICTEST_FIREBIRD_ODBC_DSN}
_USER and _PASS to run this test'.
Warning: This test drops and creates a table called 'event'";
EOF
} else {
  eval "use DateTime; use DateTime::Format::Strptime;";
  if ($@) {
    plan skip_all => 'needs DateTime and DateTime::Format::Strptime for testing';
  }
}

my @info = (
  [ $dsn,  $user,  $pass  ],
  [ $dsn2, $user2, $pass2 ],
);

my $schema;

foreach my $conn_idx (0..$#info) {
  my ($dsn, $user, $pass) = @{ $info[$conn_idx] };

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => [ 'datetime_setup' ],
  });

  my $sg = Scope::Guard->new(\&cleanup);

  eval { $schema->storage->dbh->do("DROP TABLE event") };
  $schema->storage->dbh->do(<<"SQL");
  CREATE TABLE event (
    id INT PRIMARY KEY,
    created_on TIMESTAMP
  )
SQL
  my $now = DateTime->now;
  $now->set_nanosecond(555600000);
  my $row;
  ok( $row = $schema->resultset('Event')->create({
        id => 1,
        created_on => $now,
      }));
  ok( $row = $schema->resultset('Event')
    ->search({ id => 1 }, { select => ['created_on'] })
    ->first
  );
  is $row->created_on, $now, 'DateTime roundtrip';

  if ($conn_idx == 0) { # skip for ODBC
    cmp_ok $row->created_on->nanosecond, '==', 555600000,
      'fractional part of a second survived';
  }
}

done_testing;

# clean up our mess
sub cleanup {
  my $dbh; 
  eval {
    $schema->storage->disconnect; # to avoid object FOO is in use errors
    $dbh = $schema->storage->dbh;
  };
  return unless $dbh;

  eval { $dbh->do("DROP TABLE $_") } for qw/event/;
}

use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Scope::Guard ();

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_INFORMIX_${_}" } qw/DSN USER PASS/};

if (not $dsn) {
  plan skip_all => <<'EOF';
Set $ENV{DBICTEST_INFORMIX_DSN} _USER and _PASS to run this test'.
Warning: This test drops and creates a table called 'event'";
EOF
} else {
  eval "use DateTime; use DateTime::Format::Strptime;";
  if ($@) {
    plan skip_all => 'needs DateTime and DateTime::Format::Strptime for testing';
  }
}

my $schema;

{
  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => [ 'datetime_setup' ],
  });

  my $sg = Scope::Guard->new(\&cleanup);

  eval { $schema->storage->dbh->do('DROP TABLE event') };
  $schema->storage->dbh->do(<<'SQL');
  CREATE TABLE event (
    id INT PRIMARY KEY,
    starts_at DATE,
    created_on DATETIME YEAR TO FRACTION(5)
  );
SQL
  my $rs = $schema->resultset('Event');

  my $dt = DateTime->now;
  $dt->set_nanosecond(555640000);

  my $date_only = DateTime->new(
    year => $dt->year, month => $dt->month, day => $dt->day
  );

  my $row;
  ok( $row = $rs->create({
    id => 1,
    starts_at => $date_only, 
    created_on => $dt,
  }));
  ok( $row = $rs->search({ id => 1 }, { select => [qw/starts_at created_on/] })
    ->first
  );
  is $row->created_on, $dt, 'TIMESTAMP as DateTime roundtrip';

  cmp_ok $row->created_on->nanosecond, '==', $dt->nanosecond,
    'fractional part of a second survived';

  is $row->starts_at, $date_only, 'DATE as DateTime roundtrip';
}

done_testing;

# clean up our mess
sub cleanup {
  my $dbh; 
  eval {
    $dbh = $schema->storage->dbh;
  };
  return unless $dbh;

  eval { $dbh->do(qq{DROP TABLE $_}) } for qw/event/;
}

use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;
use Scope::Guard ();

my ($dsn, $user, $pass)    = @ENV{map { "DBICTEST_FIREBIRD_${_}" }      qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_FIREBIRD_INTERBASE_${_}" } qw/DSN USER PASS/};
my ($dsn3, $user3, $pass3) = @ENV{map { "DBICTEST_FIREBIRD_ODBC_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Test needs ' .
  (join ' and ', map { $_ ? $_ : () }
    DBIx::Class::Optional::Dependencies->req_missing_for('test_dt'),
    (join ' or ', map { $_ ? $_ : () }
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_firebird'),
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_firebird_interbase'),
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_firebird_odbc')))
  unless
    DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt') && (
    $dsn && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_firebird')
    or
    $dsn2 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_firebird_interbase')
    or
    $dsn3 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_firebird_odbc'))
      or (not $dsn || $dsn2 || $dsn3);

if (not ($dsn || $dsn2)) {
  plan skip_all => <<'EOF';
Set $ENV{DBICTEST_FIREBIRD_DSN} and/or $ENV{DBICTEST_FIREBIRD_INTERBASE_DSN}
and/or $ENV{DBICTEST_FIREBIRD_ODBC_DSN}
_USER and _PASS to run this test'.
Warning: This test drops and creates a table called 'event'";
EOF
}

my @info = (
  [ $dsn,  $user,  $pass  ],
  [ $dsn2, $user2, $pass2 ],
  [ $dsn3, $user3, $pass3 ],
);

my $schema;

foreach my $conn_idx (0..$#info) {
  my ($dsn, $user, $pass) = @{ $info[$conn_idx] || [] };

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    quote_char => '"',
    name_sep   => '.',
    on_connect_call => [ 'datetime_setup' ],
  });

  my $sg = Scope::Guard->new(\&cleanup);

  eval { $schema->storage->dbh->do('DROP TABLE "event"') };
  $schema->storage->dbh->do(<<'SQL');
  CREATE TABLE "event" (
    "id" INT PRIMARY KEY,
    "starts_at" DATE,
    "created_on" TIMESTAMP
  )
SQL
  my $rs = $schema->resultset('Event');

  my $dt = DateTime->now;
  $dt->set_nanosecond(555600000);

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
    $schema->storage->disconnect; # to avoid object FOO is in use errors
    $dbh = $schema->storage->dbh;
  };
  return unless $dbh;

  eval { $dbh->do(qq{DROP TABLE "$_"}) } for qw/event/;
}

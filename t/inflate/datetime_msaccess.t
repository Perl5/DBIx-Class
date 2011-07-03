use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_MSACCESS_ODBC_${_}" } qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_MSACCESS_ADO_${_}" }  qw/DSN USER PASS/};

plan skip_all => 'Test needs ' .
  (join ' and ', map { $_ ? $_ : () }
    DBIx::Class::Optional::Dependencies->req_missing_for('test_dt'),
    (join ' or ', map { $_ ? $_ : () }
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_msaccess_odbc'),
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_msaccess_ado')))
  unless
    DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt') && (
    $dsn && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_msaccess_odbc')
    or
    $dsn2 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_msaccess_ado'))
      or (not $dsn || $dsn2);

plan skip_all => <<'EOF' unless $dsn || $dsn2;
Set $ENV{DBICTEST_MSACCESS_ODBC_DSN} and/or $ENV{DBICTEST_MSACCESS_ADO_DSN} (and optionally _USER and _PASS) to run these tests.
Warning: this test drops and creates the table 'track'.
EOF

my @connect_info = (
  [ $dsn,  $user  || '', $pass  || '' ],
  [ $dsn2, $user2 || '', $pass2 || '' ],
);

my $schema;

for my $connect_info (@connect_info) {
  my ($dsn, $user, $pass) = @$connect_info;

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup',
    quote_names => 1,
  });

  my $guard = Scope::Guard->new(\&cleanup);

  try { local $^W = 0; $schema->storage->dbh->do('DROP TABLE track') };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
  trackid AUTOINCREMENT PRIMARY KEY,
  cd INT,
  [position] INT,
  last_updated_at DATETIME
)
SQL

  ok(my $dt = DateTime->new({
    year => 2004,
    month => 8,
    day => 21,
    hour => 14,
    minute => 36,
    second => 48,
  }));

  ok(my $row = $schema->resultset('Track')->create({
    last_updated_at => $dt,
    cd => 1
  }));
  ok($row = $schema->resultset('Track')
    ->search({ trackid => $row->trackid }, { select => ['last_updated_at'] })
    ->first
  );
  is($row->last_updated_at, $dt, "DATETIME roundtrip" );
}

done_testing;

# clean up our mess
sub cleanup {
  # have to reconnect to drop a table that's in use
  if (my $storage = eval { $schema->storage }) {
    local $^W = 0;
    $storage->disconnect;
    $storage->dbh->do('DROP TABLE track');
  }
}

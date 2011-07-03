use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_MSSQL_${_}" }      qw/DSN USER PASS/};
my ($dsn3, $user3, $pass3) = @ENV{map { "DBICTEST_MSSQL_ADO_${_}" }  qw/DSN USER PASS/};

plan skip_all => 'Test needs ' .
  (join ' and ', map { $_ ? $_ : () }
    DBIx::Class::Optional::Dependencies->req_missing_for('test_dt'),
    (join ' or ', map { $_ ? $_ : () }
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_mssql_odbc'),
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_mssql_sybase'),
      DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_mssql_ado')))
  unless
    DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt') && (
    $dsn && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_mssql_odbc')
    or
    $dsn2 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_mssql_sybase')
    or
    $dsn3 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_mssql_ado'))
      or (not $dsn || $dsn2 || $dsn3);

# use this if you keep a copy of DBD::Sybase linked to FreeTDS somewhere else
BEGIN {
  if (my $lib_dirs = $ENV{DBICTEST_MSSQL_PERL5LIB}) {
    unshift @INC, $_ for split /:/, $lib_dirs;
  }
}

if (not ($dsn || $dsn2 || $dsn3)) {
  plan skip_all =>
    'Set $ENV{DBICTEST_MSSQL_ODBC_DSN} and/or $ENV{DBICTEST_MSSQL_DSN} and/or '
    .'$ENV{DBICTEST_MSSQL_ADO_DSN} _USER and _PASS to run this test' .
    "\nWarning: This test drops and creates tables called 'event_small_dt' and"
    ." 'track'.";
}

DBICTest::Schema->load_classes('EventSmallDT');

my @connect_info = (
  [ $dsn,  $user,  $pass ],
  [ $dsn2, $user2, $pass2 ],
  [ $dsn3, $user3, $pass3 ],
);

my $schema;

SKIP:
for my $connect_info (@connect_info) {
  my ($dsn, $user, $pass) = @$connect_info;

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup'
  });

  {
    my $w;
    local $SIG{__WARN__} = sub { $w = shift };
    $schema->storage->ensure_connected;
    if ($w =~ /Your DBD::Sybase is too old to support DBIx::Class::InflateColumn::DateTime/) {
      skip "Skipping tests on old DBD::Sybase " . DBD::Sybase->VERSION, 1;
    }
  }

  my $guard = Scope::Guard->new(\&cleanup);

  # $^W because DBD::ADO is a piece of crap
  try { local $^W = 0; $schema->storage->dbh->do("DROP TABLE track") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
 trackid INT IDENTITY PRIMARY KEY,
 cd INT,
 position INT,
 last_updated_at DATETIME,
)
SQL
  try { local $^W = 0; $schema->storage->dbh->do("DROP TABLE event_small_dt") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE event_small_dt (
 id INT IDENTITY PRIMARY KEY,
 small_dt SMALLDATETIME,
)
SQL

# coltype, column, source, pk, create_extra, datehash
  my @dt_types = (
    ['DATETIME',
     'last_updated_at',
     'Track',
     'trackid',
     { cd => 1 },
     {
      year => 2004,
      month => 8,
      day => 21,
      hour => 14,
      minute => 36,
      second => 48,
      nanosecond => 500000000,
    }],
    ['SMALLDATETIME', # minute precision
     'small_dt',
     'EventSmallDT',
     'id',
     {},
     {
      year => 2004,
      month => 8,
      day => 21,
      hour => 14,
      minute => 36,
    }],
  );

  for my $dt_type (@dt_types) {
    my ($type, $col, $source, $pk, $create_extra, $sample_dt) = @$dt_type;

    delete $sample_dt->{nanosecond} if $dsn =~ /:ADO:/;

    ok(my $dt = DateTime->new($sample_dt));

    my $row;
    ok( $row = $schema->resultset($source)->create({
          $col => $dt,
          %$create_extra,
        }));
    ok( $row = $schema->resultset($source)
      ->search({ $pk => $row->$pk }, { select => [$col] })
      ->first
    );
    is( $row->$col, $dt, "$type roundtrip" );

    cmp_ok( $row->$col->nanosecond, '==', $sample_dt->{nanosecond},
      'DateTime fractional portion roundtrip' )
      if exists $sample_dt->{nanosecond};
  }
}

done_testing;

# clean up our mess
sub cleanup {
  if (my $dbh = eval { $schema->storage->dbh }) {
    $dbh->do('DROP TABLE track');
    $dbh->do('DROP TABLE event_small_dt');
  }
}

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

DBICTest::Schema->load_classes('EventSmallDT');

# use this if you keep a copy of DBD::Sybase linked to FreeTDS somewhere else
BEGIN {
  if (my $lib_dirs = $ENV{DBICTEST_MSSQL_PERL5LIB}) {
    unshift @INC, $_ for split /:/, $lib_dirs;
  }
}

my ($dsn, $user, $pass)    = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_MSSQL_${_}" }      qw/DSN USER PASS/};

if (not ($dsn || $dsn2)) {
  plan skip_all =>
    'Set $ENV{DBICTEST_MSSQL_ODBC_DSN} and/or $ENV{DBICTEST_MSSQL_DSN} _USER '
    .'and _PASS to run this test' .
    "\nWarning: This test drops and creates a table called 'small_dt'";
}

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_dt')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt');

my @connect_info = (
  [ $dsn,  $user,  $pass ],
  [ $dsn2, $user2, $pass2 ],
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

  try { $schema->storage->dbh->do("DROP TABLE track") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
 trackid INT IDENTITY PRIMARY KEY,
 cd INT,
 position INT,
 last_updated_at DATETIME,
)
SQL
  try { $schema->storage->dbh->do("DROP TABLE event_small_dt") };
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

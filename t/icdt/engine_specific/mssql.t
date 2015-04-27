use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt _rdbms_mssql_common );

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

my @tdeps = qw( test_rdbms_mssql_odbc test_rdbms_mssql_sybase test_rdbms_mssql_ado );
plan skip_all => 'Test needs  ' . (join '  OR  ', map
  { "[ @{[ DBIx::Class::Optional::Dependencies->req_missing_for( $_ ) ]} ]" }
  @tdeps
) unless scalar grep
  { DBIx::Class::Optional::Dependencies->req_ok_for( $_ ) }
  @tdeps
;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_MSSQL_${_}" }      qw/DSN USER PASS/};
my ($dsn3, $user3, $pass3) = @ENV{map { "DBICTEST_MSSQL_ADO_${_}" }  qw/DSN USER PASS/};

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

  my $guard = Scope::Guard->new(sub{ cleanup($schema) });

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
  try { local $^W = 0; $schema->storage->dbh->do("DROP TABLE event") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE event (
   id int IDENTITY(1,1) NOT NULL,
   starts_at smalldatetime NULL,
   created_on datetime NULL,
   varchar_date varchar(20) NULL,
   varchar_datetime varchar(20) NULL,
   skip_inflation datetime NULL,
   ts_without_tz datetime NULL
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

  # Check for bulk insert SQL_DATE funtimes when using DBD::ODBC and sqlncli
  # dbi:ODBC:driver=SQL Server Native Client 10.0;server=10.6.0.9;database=odbctest;
  lives_ok {
    $schema->resultset('Event')->populate([{
      id => 1,
      starts_at => undef,
    },{
      id => 2,
      starts_at => '2011-03-22',
    }])
  } 'populate with datetime does not throw';
  ok ( my $row = $schema->resultset('Event')->find(2), 'SQL_DATE bulk insert check' );
}


done_testing;

# clean up our mess
sub cleanup {
  my $schema = shift;
  if (my $dbh = eval { $schema->storage->dbh }) {
    $dbh->do('DROP TABLE track');
    $dbh->do('DROP TABLE event_small_dt');
    $dbh->do('DROP TABLE event');
  }
}

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_dt')
. ' and ' .
DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_ase')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt')
    && DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_ase');

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_SYBASE_${_}" } qw/DSN USER PASS/};

if (not ($dsn && $user)) {
  plan skip_all =>
    'Set $ENV{DBICTEST_SYBASE_DSN}, _USER and _PASS to run this test' .
    "\nWarning: This test drops and creates a table called 'track' and " .
    "'event_small_dt'";
}

DBICTest::Schema->load_classes('EventSmallDT');

my @storage_types = (
  'DBI::Sybase::ASE',
  'DBI::Sybase::ASE::NoBindVars',
);
my $schema;

for my $storage_type (@storage_types) {
  $schema = DBICTest::Schema->clone;

  unless ($storage_type eq 'DBI::Sybase::ASE') { # autodetect
    $schema->storage_type("::$storage_type");
  }
  $schema->connection($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup',
  });

  my $guard = Scope::Guard->new(\&cleanup);

  $schema->storage->ensure_connected;

  isa_ok( $schema->storage, "DBIx::Class::Storage::$storage_type" );

  eval { $schema->storage->dbh->do("DROP TABLE track") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
    trackid INT IDENTITY PRIMARY KEY,
    cd INT NULL,
    position INT NULL,
    last_updated_at DATETIME NULL
)
SQL
  eval { $schema->storage->dbh->do("DROP TABLE event_small_dt") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE event_small_dt (
    id INT IDENTITY PRIMARY KEY,
    small_dt SMALLDATETIME NULL,
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

  # test a computed datetime column
  eval { $schema->storage->dbh->do("DROP TABLE track") };
  $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
    trackid INT IDENTITY PRIMARY KEY,
    cd INT NULL,
    position INT NULL,
    title VARCHAR(100) NULL,
    last_updated_on DATETIME NULL,
    last_updated_at AS getdate(),
)
SQL

  my $now = DateTime->now;
  sleep 1;
  my $new_row = $schema->resultset('Track')->create({});
  $new_row->discard_changes;

  lives_and {
    cmp_ok (($new_row->last_updated_at - $now)->seconds, '>=', 1)
  } 'getdate() computed column works';
}

done_testing;

# clean up our mess
sub cleanup {
  if (my $dbh = eval { $schema->storage->dbh }) {
    $dbh->do('DROP TABLE track');
    $dbh->do('DROP TABLE event_small_dt');
  }
}

use strict;
use warnings;  

use Test::More;
use Test::Exception;
use Scope::Guard ();
use lib qw(t/lib);
use DBICTest;

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
    "\nWarning: This test drops and creates a table called 'track'";
} else {
  eval "use DateTime; use DateTime::Format::Strptime;";
  if ($@) {
    plan skip_all => 'needs DateTime and DateTime::Format::Strptime for testing';
  }
}

my @connect_info = (
  [ $dsn,  $user,  $pass ],
  [ $dsn2, $user2, $pass2 ],
);

my $schema;

for my $connect_info (@connect_info) {
  my ($dsn, $user, $pass) = @$connect_info;

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup'
  });

  my $guard = Scope::Guard->new(\&cleanup);

# coltype, column, datehash
  my @dt_types = (
    ['DATETIME',
     'last_updated_at',
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
     {
      year => 2004,
      month => 8,
      day => 21,
      hour => 14,
      minute => 36,
    }],
  );

  for my $dt_type (@dt_types) {
    my ($type, $col, $sample_dt) = @$dt_type;

    eval { $schema->storage->dbh->do("DROP TABLE track") };
    $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
 trackid INT IDENTITY PRIMARY KEY,
 cd INT,
 position INT,
 $col $type,
)
SQL
    ok(my $dt = DateTime->new($sample_dt));

    my $row;
    ok( $row = $schema->resultset('Track')->create({
          $col => $dt,
          cd => 1,
        }));
    ok( $row = $schema->resultset('Track')
      ->search({ trackid => $row->trackid }, { select => [$col] })
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
  }
}

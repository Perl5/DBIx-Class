use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt _rdbms_msaccess_common );

use strict;
use warnings;

use Test::More;
use Scope::Guard ();
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

my @tdeps = qw( test_rdbms_msaccess_odbc test_rdbms_msaccess_ado );
plan skip_all => 'Test needs  ' . (join '  OR  ', map
  { "[ @{[ DBIx::Class::Optional::Dependencies->req_missing_for( $_ ) ]} ]" }
  @tdeps
) unless scalar grep
  { DBIx::Class::Optional::Dependencies->req_ok_for( $_ ) }
  @tdeps
;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_MSACCESS_ODBC_${_}" } qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_MSACCESS_ADO_${_}" }  qw/DSN USER PASS/};

my @connect_info = (
  [ $dsn,  $user  || '', $pass  || '' ],
  [ $dsn2, $user2 || '', $pass2 || '' ],
);

for my $connect_info (@connect_info) {
  my ($dsn, $user, $pass) = @$connect_info;

  next unless $dsn;

  my $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup',
    quote_names => 1,
  });

  my $guard = Scope::Guard->new(sub { cleanup($schema) });

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
  my $schema = shift;
  # have to reconnect to drop a table that's in use
  if (my $storage = eval { $schema->storage }) {
    local $^W = 0;
    $storage->disconnect;
    $storage->dbh->do('DROP TABLE track');
  }
}

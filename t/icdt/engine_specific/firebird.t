use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt _rdbms_firebird_common );

use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use Scope::Guard ();

my $env2optdep = {
  DBICTEST_FIREBIRD => 'test_rdbms_firebird',
  DBICTEST_FIREBIRD_INTERBASE => 'test_rdbms_firebird_interbase',
  DBICTEST_FIREBIRD_ODBC => 'test_rdbms_firebird_odbc',
};

my @tdeps = values %$env2optdep;
plan skip_all => 'Test needs  ' . (join '  OR  ', map
  { "[ @{[ DBIx::Class::Optional::Dependencies->req_missing_for( $_ ) ]} ]" }
  @tdeps
) unless scalar grep
  { DBIx::Class::Optional::Dependencies->req_ok_for( $_ ) }
  @tdeps
;

my $schema;

for my $prefix (keys %$env2optdep) { SKIP: {

  my ($dsn, $user, $pass) = map { $ENV{"${prefix}_$_"} } qw/DSN USER PASS/;

  next unless $dsn;

  note "Testing with ${prefix}_DSN";

  skip ("Testing with ${prefix}_DSN needs " . DBIx::Class::Optional::Dependencies->req_missing_for( $env2optdep->{$prefix} ), 1)
    unless  DBIx::Class::Optional::Dependencies->req_ok_for($env2optdep->{$prefix});

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    quote_char => '"',
    name_sep   => '.',
    on_connect_call => [ 'datetime_setup' ],
  });

  my $sg = Scope::Guard->new(sub { cleanup($schema) } );

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
} }

done_testing;

# clean up our mess
sub cleanup {
  my $schema = shift;
  my $dbh;
  eval {
    $schema->storage->disconnect; # to avoid object FOO is in use errors
    $dbh = $schema->storage->dbh;
  };
  return unless $dbh;

  eval { $dbh->do(qq{DROP TABLE "$_"}) } for qw/event/;
}

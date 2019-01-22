use strict;
use warnings;

use Test::More;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;
use Scope::Guard ();

my $env2optdep = {
  DBICTEST_FIREBIRD => 'test_rdbms_firebird',
  DBICTEST_FIREBIRD_INTERBASE => 'test_rdbms_firebird_interbase',
  DBICTEST_FIREBIRD_ODBC => 'test_rdbms_firebird_odbc',
};

plan skip_all => join (' ',
  'Set $ENV{DBICTEST_FIREBIRD_DSN} and/or $ENV{DBICTEST_FIREBIRD_INTERBASE_DSN}',
  'and/or $ENV{DBICTEST_FIREBIRD_ODBC_DSN},',
  '_USER and _PASS to run these tests.',

  "WARNING: This test drops and creates a table called 'event'",
) unless grep { $ENV{"${_}_DSN"} } keys %$env2optdep;

plan skip_all => ( 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for('test_dt') )
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_dt');

my $schema;

for my $prefix (keys %$env2optdep) { SKIP: {

  my ($dsn, $user, $pass) = map { $ENV{"${prefix}_$_"} } qw/DSN USER PASS/;
  next unless $dsn;


  # FIXME - work around https://github.com/google/sanitizers/issues/934
  $prefix eq 'DBICTEST_FIREBIRD_ODBC'
    and
  $Config::Config{config_args} =~ m{fsanitize\=address}
    and
  skip( "ODBC Firebird driver doesn't yet work with ASAN: https://github.com/google/sanitizers/issues/934", 1 );


  skip ("Testing with ${prefix}_DSN needs " . DBIx::Class::Optional::Dependencies->req_missing_for( $env2optdep->{$prefix} ), 1)
    unless  DBIx::Class::Optional::Dependencies->req_ok_for($env2optdep->{$prefix});

  note "Testing with ${prefix}_DSN";

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

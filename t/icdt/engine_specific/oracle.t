use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt test_rdbms_oracle );

use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

# DateTime::Format::Oracle needs this set
$ENV{NLS_DATE_FORMAT} = 'DD-MON-YY';
$ENV{NLS_TIMESTAMP_FORMAT} = 'YYYY-MM-DD HH24:MI:SSXFF';
$ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';
$ENV{NLS_SORT} = "BINARY";
$ENV{NLS_COMP} = "BINARY";

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_ORA_${_}" } qw/DSN USER PASS/};
my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

# older oracles do not support a TIMESTAMP datatype
my $timestamp_datatype = ($schema->storage->_server_info->{normalized_dbms_version}||0) < 9
  ? 'DATE'
  : 'TIMESTAMP'
;

my $dbh = $schema->storage->dbh;

#$dbh->do("alter session set nls_timestamp_format = 'YYYY-MM-DD HH24:MI:SSXFF'");

eval {
  $dbh->do("DROP TABLE event");
};
$dbh->do(<<EOS);
  CREATE TABLE event (
    id number NOT NULL,
    starts_at date NOT NULL,
    created_on $timestamp_datatype NOT NULL,
    varchar_date varchar(20),
    varchar_datetime varchar(20),
    skip_inflation date,
    ts_without_tz date,
    PRIMARY KEY (id)
  )
EOS

# TODO is in effect for the rest of the tests
local $TODO = 'FIXME - something odd is going on with Oracle < 9 datetime support'
  if ($schema->storage->_server_info->{normalized_dbms_version}||0) < 9;

lives_ok {

# insert a row to play with
my $new = $schema->resultset('Event')->create({ id => 1, starts_at => '06-MAY-07', created_on => '2009-05-03 21:17:18.5' });
is($new->id, 1, "insert sucessful");

my $event = $schema->resultset('Event')->find( 1 );

is( ref($event->starts_at), 'DateTime', "starts_at inflated ok");

is( $event->starts_at->month, 5, "DateTime methods work on inflated column");

is( ref($event->created_on), 'DateTime', "created_on inflated ok");

is( $event->created_on->nanosecond, 500_000_000, "DateTime methods work with nanosecond precision");

my $dt = DateTime->now();
$event->starts_at($dt);
$event->created_on($dt);
$event->update;

is( $event->starts_at->month, $dt->month, "deflate ok");
is( int $event->created_on->nanosecond, int $dt->nanosecond, "deflate ok with nanosecond precision");

# test datetime_setup

$schema->storage->disconnect;

delete $ENV{NLS_DATE_FORMAT};
delete $ENV{NLS_TIMESTAMP_FORMAT};

$schema->connection($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup'
});

$dt = DateTime->now();

my $timestamp = $dt->clone;
$timestamp->set_nanosecond( int 500_000_000 );

$event = $schema->resultset('Event')->find( 1 );
$event->update({ starts_at => $dt, created_on => $timestamp });

$event = $schema->resultset('Event')->find(1);

is( $event->starts_at, $dt, 'DateTime round-trip as DATE' );
is( $event->created_on, $timestamp, 'DateTime round-trip as TIMESTAMP' );

is( int $event->created_on->nanosecond, int 500_000_000,
  'TIMESTAMP nanoseconds survived' );

} 'dateteime operations executed correctly';

done_testing;

# clean up our mess
END {
  if($schema && (my $dbh = $schema->storage->_dbh)) {
    $dbh->do("DROP TABLE event");
  }
  undef $schema;
}


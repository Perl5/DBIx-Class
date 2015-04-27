use DBIx::Class::Optional::Dependencies -skip_all_without => qw( ic_dt _rdbms_sqlanywhere_common );

use strict;
use warnings;

use Test::More;
use Scope::Guard ();
use lib qw(t/lib);
use DBICTest;

my @tdeps = qw( test_rdbms_sqlanywhere test_rdbms_sqlanywhere_odbc );
plan skip_all => 'Test needs  ' . (join '  OR  ', map
  { "[ @{[ DBIx::Class::Optional::Dependencies->req_missing_for( $_ ) ]} ]" }
  @tdeps
) unless scalar grep
  { DBIx::Class::Optional::Dependencies->req_ok_for( $_ ) }
  @tdeps
;

my ($dsn, $user, $pass)    = @ENV{map { "DBICTEST_SQLANYWHERE_${_}" }      qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_SQLANYWHERE_ODBC_${_}" } qw/DSN USER PASS/};

my @info = (
  [ $dsn,  $user,  $pass  ],
  [ $dsn2, $user2, $pass2 ],
);

my $schema;

foreach my $info (@info) {
  my ($dsn, $user, $pass) = @$info;

  next unless $dsn;

  $schema = DBICTest::Schema->clone;

  $schema->connection($dsn, $user, $pass, {
    on_connect_call => 'datetime_setup',
  });

  my $sg = Scope::Guard->new(sub { cleanup($schema) } );

  eval { $schema->storage->dbh->do('DROP TABLE event') };
  $schema->storage->dbh->do(<<"SQL");
  CREATE TABLE event (
    id INT IDENTITY PRIMARY KEY,
    created_on TIMESTAMP,
    starts_at DATE
  )
SQL

# coltype, col, date
  my @dt_types = (
    [
      'TIMESTAMP',
      'created_on',
      '2004-08-21 14:36:48.080445',
    ],
# date only (but minute precision according to ASA docs)
    [
      'DATE',
      'starts_at',
      '2004-08-21 00:00:00.000000',
    ],
  );

  for my $dt_type (@dt_types) {
    my ($type, $col, $sample_dt) = @$dt_type;

    ok(my $dt = $schema->storage->datetime_parser->parse_datetime($sample_dt));

    my $row;
    ok( $row = $schema->resultset('Event')->create({ $col => $dt, }));
    ok( $row = $schema->resultset('Event')
      ->search({ id => $row->id }, { select => [$col] })
      ->first
    );
    is( $row->$col, $dt, "$type roundtrip" );

    is $row->$col->nanosecond, $dt->nanosecond,
        'nanoseconds survived' if 0+$dt->nanosecond;
  }
}

done_testing;

# clean up our mess
sub cleanup {
  my $schema = shift;
  if (my $dbh = $schema->storage->dbh) {
    eval { $dbh->do("DROP TABLE $_") } for qw/event/;
  }
}

use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DateTime::Format::Sybase;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_SYBASE_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_SYBASE_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => (26 + 4*2)*2;

my @storage_types = (
  'DBI::Sybase',
  'DBI::Sybase::NoBindVars',
);
my $schema;

for my $storage_type (@storage_types) {
  $schema = DBICTest::Schema->clone;

  unless ($storage_type eq 'DBI::Sybase') { # autodetect
    $schema->storage_type("::$storage_type");
  }
  $schema->connection($dsn, $user, $pass, {AutoCommit => 1});

  $schema->storage->ensure_connected;

  isa_ok( $schema->storage, "DBIx::Class::Storage::$storage_type" );

  $schema->storage->dbh_do (sub {
      my ($storage, $dbh) = @_;
      eval { $dbh->do("DROP TABLE artist") };
      $dbh->do(<<'SQL');
CREATE TABLE artist (
   artistid INT IDENTITY PRIMARY KEY,
   name VARCHAR(100),
   rank INT DEFAULT 13 NOT NULL,
   charfield CHAR(10) NULL
)
SQL
  });

  my %seen_id;

# so we start unconnected
  $schema->storage->disconnect;

# test primary key handling
  my $new = $schema->resultset('Artist')->create({ name => 'foo' });
  ok($new->artistid > 0, "Auto-PK worked");

  $seen_id{$new->artistid}++;

  for (1..6) {
    $new = $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
    is ( $seen_id{$new->artistid}, undef, "id for Artist $_ is unique" );
    $seen_id{$new->artistid}++;
  }

# test simple count
  is ($schema->resultset('Artist')->count, 7, 'count(*) of whole table ok');

# test LIMIT support
  my $it = $schema->resultset('Artist')->search({
    artistid => { '>' => 0 }
  }, {
    rows => 3,
    order_by => 'artistid',
  });

  is( $it->count, 3, "LIMIT count ok" );

  is( $it->next->name, "foo", "iterator->next ok" );
  $it->next;
  is( $it->next->name, "Artist 2", "iterator->next ok" );
  is( $it->next, undef, "next past end of resultset ok" );

# now try with offset
  $it = $schema->resultset('Artist')->search({}, {
    rows => 3,
    offset => 3,
    order_by => 'artistid',
  });

  is( $it->count, 3, "LIMIT with offset count ok" );

  is( $it->next->name, "Artist 3", "iterator->next ok" );
  $it->next;
  is( $it->next->name, "Artist 5", "iterator->next ok" );
  is( $it->next, undef, "next past end of resultset ok" );

# now try a grouped count
  $schema->resultset('Artist')->create({ name => 'Artist 6' })
    for (1..6);

  $it = $schema->resultset('Artist')->search({}, {
    group_by => 'name'
  });

  is( $it->count, 7, 'COUNT of GROUP_BY ok' );

# Test DateTime inflation with DATETIME
  my @dt_types = (
    ['DATETIME', '2004-08-21T14:36:48.080Z'],
    ['SMALLDATETIME', '2004-08-21T14:36:00.000Z'], # minute precision
  );
  
  for my $dt_type (@dt_types) {
    my ($type, $sample_dt) = @$dt_type;

    eval { $schema->storage->dbh->do("DROP TABLE track") };
    $schema->storage->dbh->do(<<"SQL");
CREATE TABLE track (
   trackid INT IDENTITY PRIMARY KEY,
   cd INT,
   position INT,
   last_updated_on $type,
)
SQL
    ok(my $dt = DateTime::Format::Sybase->parse_datetime($sample_dt));

    my $row;
    ok( $row = $schema->resultset('Track')->create({
      last_updated_on => $dt,
      cd => 1,
    }));
    ok( $row = $schema->resultset('Track')
      ->search({ trackid => $row->trackid }, { select => ['last_updated_on'] })
      ->first
    );
    is( $row->updated_date, $dt, 'DateTime inflation works' );
  }

# mostly stole the blob stuff Nniuq wrote for t/73oracle.t
  my $dbh = $schema->storage->dbh;
  {
    local $SIG{__WARN__} = sub {};
    eval { $dbh->do('DROP TABLE bindtype_test') };

    $dbh->do(qq[
      CREATE TABLE bindtype_test 
      (
        id    INT   PRIMARY KEY,
        bytea INT   NULL,
        blob  IMAGE NULL,
        clob  TEXT  NULL
      )
    ],{ RaiseError => 1, PrintError => 1 });
  }

  my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
  $binstr{'large'} = $binstr{'small'} x 1024;

  my $maxloblen = length $binstr{'large'};
  note "Localizing LongReadLen to $maxloblen to avoid truncation of test data";
  local $dbh->{'LongReadLen'} = $maxloblen;

  my $rs = $schema->resultset('BindType');
  my $id = 0;

  foreach my $type (qw(blob clob)) {
    foreach my $size (qw(small large)) {
      no warnings 'uninitialized';
      $id++;

      eval { $rs->create( { 'id' => $id, $type => $binstr{$size} } ) };
      ok(!$@, "inserted $size $type without dying");
      diag $@ if $@;

      ok(eval {
        $rs->search({ id=> $id }, { select => [$type] })->single->$type
      } eq $binstr{$size}, "verified inserted $size $type" );
    }
  }
}

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->_dbh }) {
    $dbh->do('DROP TABLE artist');
    $dbh->do('DROP TABLE track');
    $dbh->do('DROP TABLE bindtype_test');
  }
}

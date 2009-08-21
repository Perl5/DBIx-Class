use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_ADO_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_ADO_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 10;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);
$schema->storage->ensure_connected;

isa_ok( $schema->storage, 'DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server' );

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { $dbh->do("DROP TABLE artist") };
    $dbh->do(<<'SQL');
CREATE TABLE artist (
   artistid INT IDENTITY NOT NULL,
   name VARCHAR(100),
   rank INT NOT NULL DEFAULT '13',
   charfield CHAR(10) NULL,
   primary key(artistid)
)
SQL
});

my $new = $schema->resultset('Artist')->create({ name => 'foo' });
ok($new->artistid > 0, 'Auto-PK worked');

# make sure select works
my $found = $schema->resultset('Artist')->search({ name => 'foo' })->first;
is $found->artistid, $new->artistid, 'search works';

# create a few more rows
for (1..6) {
  $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}

# test multiple active cursors
my $rs1 = $schema->resultset('Artist');
my $rs2 = $schema->resultset('Artist');

while ($rs1->next) {
  ok eval { $rs2->next }, 'multiple active cursors';
}

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->_dbh }) {
    eval { $dbh->do("DROP TABLE $_") }
      for qw/artist/;
  }
}
# vim:sw=2 sts=2

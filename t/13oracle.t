use lib qw(lib t/lib);
use DBICTest::Schema;

use Test::More;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_ORA_${_}" } qw/DSN USER PASS/};

plan skip_all, 'Set $ENV{DBICTEST_ORA_DSN}, _USER and _PASS to run this test. ' .
  'Warning: This test drops and creates a table called \'artist\''
  unless ($dsn && $user && $pass);

plan tests => 1;

DBICTest::Schema->compose_connection('OraTest' => $dsn, $user, $pass);

my $dbh = OraTest::Artist->storage->dbh;

eval {
  $dbh->do("DROP SEQUENCE artist_seq");
  $dbh->do("DROP TABLE artist");
};
$dbh->do("CREATE SEQUENCE artist_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
$dbh->do("CREATE TABLE artist (artistid NUMBER(12), name VARCHAR(255))");
$dbh->do("ALTER TABLE artist ADD (CONSTRAINT artist_pk PRIMARY KEY (artistid))");
$dbh->do(qq{
  CREATE OR REPLACE TRIGGER artist_insert_trg
  BEFORE INSERT ON artist
  FOR EACH ROW
  BEGIN
    IF :new.artistid IS NULL THEN
      SELECT artist_seq.nextval
      INTO :new.artistid
      FROM DUAL;
    END IF;
  END;
});

OraTest::Artist->load_components('PK::Auto::Oracle');

my $new = OraTest::Artist->create({ name => 'foo' });

ok($new->artistid, "Oracle Auto-PK worked");

$dbh->do("DROP SEQUENCE artist_seq");
$dbh->do("DROP TABLE artist");

1;

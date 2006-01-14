sub run_tests {
my $schema = shift;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_ORA_${_}" } qw/DSN USER PASS/};

plan skip_all, 'Set $ENV{DBICTEST_ORA_DSN}, _USER and _PASS to run this test. ' .
  'Warning: This test drops and creates a table called \'artist\''
  unless ($dsn && $user && $pass);

plan tests => 4;

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

# test primary key handling
my $new = OraTest::Artist->create({ name => 'foo' });
is($new->artistid, 1, "Oracle Auto-PK worked");

# test LIMIT support
for (1..6) {
    OraTest::Artist->create({ name => 'Artist ' . $_ });
}
my $it = OraTest::Artist->search( {},
    { rows => 3,
      offset => 2,
      order_by => 'artistid' }
);
is( $it->count, 3, "LIMIT count ok" );
is( $it->next->name, "Artist 2", "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

# clean up our mess
$dbh->do("DROP SEQUENCE artist_seq");
$dbh->do("DROP TABLE artist");

}

1;

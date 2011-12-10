use strict;
use warnings;

use Test::More;
use DBIx::Class::Optional::Dependencies ();
use Try::Tiny;
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('rdbms_pg')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('rdbms_pg');

my ($dsn, $dbuser, $dbpass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $dbuser);

my $schema = DBICTest::Schema->connection($dsn, $dbuser, $dbpass, { AutoCommit => 1 });

if ($schema->storage->_server_info->{normalized_dbms_version} >= 9.0) {
  if (not try { DBD::Pg->VERSION('2.17.2') }) {
    plan skip_all =>
      'DBD::Pg < 2.17.2 does not work with Pg >= 9.0 BYTEA columns';
  }
}
elsif (not try { DBD::Pg->VERSION('2.9.2') }) {
  plan skip_all =>
    'DBD::Pg < 2.9.2 does not work with BYTEA columns';
}

my $dbh = $schema->storage->dbh;

{
    local $SIG{__WARN__} = sub {};
    $dbh->do('DROP TABLE IF EXISTS bindtype_test');

    # the blob/clob are for reference only, will be useful when we switch to SQLT and can test Oracle along the way
    $dbh->do(qq[
        CREATE TABLE bindtype_test
        (
            id              serial       NOT NULL   PRIMARY KEY,
            bytea           bytea        NULL,
            blob            bytea        NULL,
            clob            text         NULL,
            a_memo          text         NULL
        );
    ],{ RaiseError => 1, PrintError => 1 });
}

$schema->storage->debug(0); # these tests spew up way too much stuff, disable trace

my $big_long_string = "\x00\x01\x02 abcd" x 125000;

my $new;
# test inserting a row
{
  $new = $schema->resultset('BindType')->create({ bytea => $big_long_string });

  ok($new->id, "Created a bytea row");
  ok($new->bytea eq $big_long_string, "Set the blob correctly.");
}

# test retrieval of the bytea column
{
  my $row = $schema->resultset('BindType')->find({ id => $new->id });
  ok($row->get_column('bytea') eq $big_long_string, "Created the blob correctly.");
}

{
  my $rs = $schema->resultset('BindType')->search({ bytea => $big_long_string });

  # search on the bytea column (select)
  {
    my $row = $rs->first;
    is($row ? $row->id : undef, $new->id, "Found the row searching on the bytea column.");
  }

  # search on the bytea column (update)
  {
    my $new_big_long_string = $big_long_string . "2";
    $schema->txn_do(sub {
      $rs->update({ bytea => $new_big_long_string });
      my $row = $schema->resultset('BindType')->find({ id => $new->id });
      ok( ($row ? $row->get_column('bytea') : '') eq $new_big_long_string,
        "Updated the row correctly (searching on the bytea column)."
      );
      $schema->txn_rollback;
    });
  }

  # search on the bytea column (delete)
  {
    $schema->txn_do(sub {
      $rs->delete;
      my $row = $schema->resultset('BindType')->find({ id => $new->id });
      is($row, undef, "Deleted the row correctly (searching on the bytea column).");
      $schema->txn_rollback;
    });
  }

  # create with blob from $rs
  $new = $rs->create({});
  ok($new->bytea eq $big_long_string, 'Object has bytea value from $rs');
  $new->discard_changes;
  ok($new->bytea eq $big_long_string, 'bytea value made it to db');
}

# test inserting a row via populate() (bindtype propagation through execute_for_fetch)
# use a new $dbh to ensure no leakage due to prepare_cached
{
  my $cnt = 4;

  $schema->storage->_dbh(undef);
  my $rs = $schema->resultset('BindType');
  $rs->delete;

  $rs->populate([
    [qw/id bytea/],
    map { [
      \[ '?', [ {} => $_ ] ],
      "pop_${_}_" . $big_long_string,
    ]} (1 .. $cnt)
  ]);

  is($rs->count, $cnt, 'All rows were correctly inserted');
  for (1..$cnt) {
    my $r = $rs->find({ bytea => "pop_${_}_" . $big_long_string });
    is ($r->id, $_, "Row $_ found after find() on the blob");

  }
}

done_testing;

eval { $schema->storage->dbh_do(sub { $_[1]->do("DROP TABLE bindtype_test") } ) };


sub run_tests {
  
plan tests => 2;

# add some rows inside a transaction and commit it
# XXX: Is storage->dbh the only way to get a dbh?
DBICTest::Artist->txn_begin;
for (10..15) {
    DBICTest::Artist->create( { 
        artistid => $_,
        name => "artist number $_",
    } );
}
DBICTest::Artist->txn_commit;
my ($artist) = DBICTest::Artist->find(15);
is($artist->name, 'artist number 15', "Commit ok");

# add some rows inside a transaction and roll it back
DBICTest::Artist->txn_begin;
for (21..30) {
    DBICTest::Artist->create( {
        artistid => $_,
        name => "artist number $_",
    } );
}
DBICTest::Artist->txn_rollback;
($artist) = DBICTest::Artist->search( artistid => 25 );
is($artist, undef, "Rollback ok");

}

1;

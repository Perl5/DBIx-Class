use Test::More;

plan tests => 4;

use lib qw(t/lib);

use_ok('DBICTest');

# add some rows inside a transaction and commit it
# XXX: Is storage->dbh the only way to get a dbh?
DBICTest::Artist->storage->dbh->{AutoCommit} = 0;
for (10..15) {
    DBICTest::Artist->create( { 
        artistid => $_,
        name => "artist number $_",
    } );
}
DBICTest::Artist->dbi_commit;
my ($artist) = DBICTest::Artist->find(15);
is($artist->name, 'artist number 15', "Commit ok");

# repeat the test using AutoCommit = 1 to force the commit
DBICTest::Artist->storage->dbh->{AutoCommit} = 0;
for (16..20) {
    DBICTest::Artist->create( {
        artistid => $_,
        name => "artist number $_",
    } );
}
DBICTest::Artist->storage->dbh->{AutoCommit} = 1;
($artist) = DBICTest::Artist->find(20);
is($artist->name, 'artist number 20', "Commit using AutoCommit ok");

# add some rows inside a transaction and roll it back
DBICTest::Artist->storage->dbh->{AutoCommit} = 0;
for (21..30) {
    DBICTest::Artist->create( {
        artistid => $_,
        name => "artist number $_",
    } );
}
DBICTest::Artist->dbi_rollback;
($artist) = DBICTest::Artist->search( artistid => 25 );
is($artist, undef, "Rollback ok");


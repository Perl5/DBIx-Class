sub run_tests {
my $schema = shift;
  
plan tests => 2;

# add some rows inside a transaction and commit it
# XXX: Is storage->dbh the only way to get a dbh?
$schema->class("Artist")->txn_begin;
for (10..15) {
    $schema->class("Artist")->create( { 
        artistid => $_,
        name => "artist number $_",
    } );
}
$schema->class("Artist")->txn_commit;
my ($artist) = $schema->class("Artist")->find(15);
is($artist->name, 'artist number 15', "Commit ok");

# add some rows inside a transaction and roll it back
$schema->class("Artist")->txn_begin;
for (21..30) {
    $schema->class("Artist")->create( {
        artistid => $_,
        name => "artist number $_",
    } );
}
$schema->class("Artist")->txn_rollback;
($artist) = $schema->class("Artist")->search( artistid => 25 );
is($artist, undef, "Rollback ok");

}

1;

use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::ExplodingStorage;

plan tests => 3;

my $schema = DBICTest->init_schema();

is( ref($schema->storage), 'DBIx::Class::Storage::DBI::SQLite',
    'Storage reblessed correctly into DBIx::Class::Storage::DBI::SQLite' );


my $storage = $schema->storage;
$storage->ensure_connected;

bless $storage, "DBICTest::ExplodingStorage";
$schema->storage($storage);

eval { 
    $schema->resultset('Artist')->create({ name => "Exploding Sheep" }) 
};

is($@, "", "Exploding \$sth->execute was caught");

is(1, $schema->resultset('Artist')->search({name => "Exploding Sheep" })->count,
  "And the STH was retired");


1;

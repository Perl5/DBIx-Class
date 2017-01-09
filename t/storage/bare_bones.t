use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

use FindBin qw/$Bin/;
use File::Spec;
use File::Copy qw/copy/;

use lib qw(t/lib);
use DBICTest;

my $db_file = File::Spec->catfile( $Bin, 'bare_bones.db' );

my $test_db = DBICTest::_sqlite_dbfilename();
copy( $db_file, $test_db );

{
    package MySchema::Result::Item;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('item');
    __PACKAGE__->add_column( id => { data_type => 'INTEGER' });
}

{
    package MySchema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class( Item => 'MySchema::Result::Item' );
}

# Calling $schema->storage->dbh loads DBI and masks this bug,
# so we can't use in-memory databases to demonstrate it
# my $schema = MySchema->connect( "dbi:SQLite::memory:");
# $schema->storage->dbh->do('CREATE TABLE item( id INTEGER )');

my $schema = MySchema->connect( "dbi:SQLite:${test_db}");
is_deeply(
    [ $schema->sources ], [ 'Item' ],
    'Creating a schema with a single source'
);

# Calling deploy (which loads DBI) masks the bug I am trying to isolate
# lives_ok { $schema->deploy } 'Deploying minimal schema';

my $item;
lives_ok {
    $item = $schema->resultset('Item')->create({ id => 1 });
} 'Creating a row in a pre-existing database'
    or diag "A simple 'use DBI;' in DBIx::Class::Storage::DBI will fix this";

isa_ok( $item, 'DBIx::Class::Row' );

# clean up behind the test db to recreate it
unlink $test_db;

$schema = MySchema->connect( "dbi:SQLite:${test_db}");

lives_ok {
    $schema->deploy
} 'Deploying a copy of the schema to an in-memory DB';

lives_ok {
    $item = $schema->resultset('Item')->create({ id => 1 });
} 'deploy has loaded DBI so everything is fine now';

isa_ok( $item, 'DBIx::Class::Row' );

done_testing;

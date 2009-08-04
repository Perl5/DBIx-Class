use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBI::Const::GetInfoType;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

#warn "$dsn $user $pass";

plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 19;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

my $dbh = $schema->storage->dbh;

$dbh->do("DROP TABLE IF EXISTS artist;");

$dbh->do("CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), rank INTEGER NOT NULL DEFAULT '13', charfield CHAR(10));");

$dbh->do("DROP TABLE IF EXISTS cd;");

$dbh->do("CREATE TABLE cd (cdid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, artist INTEGER, title TEXT, year INTEGER, genreid INTEGER, single_track INTEGER);");

$dbh->do("DROP TABLE IF EXISTS producer;");

$dbh->do("CREATE TABLE producer (producerid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name TEXT);");

$dbh->do("DROP TABLE IF EXISTS cd_to_producer;");

$dbh->do("CREATE TABLE cd_to_producer (cd INTEGER,producer INTEGER);");

$dbh->do("DROP TABLE IF EXISTS owners;");

$dbh->do("CREATE TABLE owners (id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100) NOT NULL);");

$dbh->do("DROP TABLE IF EXISTS books;");

$dbh->do("CREATE TABLE books (id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, source VARCHAR(100) NOT NULL, owner integer NOT NULL, title varchar(100) NOT NULL,  price integer);");

#'dbi:mysql:host=localhost;database=dbic_test', 'dbic_test', '');

# This is in Core now, but it's here just to test that it doesn't break
$schema->class('Artist')->load_components('PK::Auto');

# test primary key handling
my $new = $schema->resultset('Artist')->create({ name => 'foo' });
ok($new->artistid, "Auto-PK worked");

# test LIMIT support
for (1..6) {
    $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}
my $it = $schema->resultset('Artist')->search( {},
    { rows => 3,
      offset => 2,
      order_by => 'artistid' }
);
is( $it->count, 3, "LIMIT count ok" );  # ask for 3 rows out of 7 artists
is( $it->next->name, "Artist 2", "iterator->next ok" );
$it->next;
$it->next;
is( $it->next, undef, "next past end of resultset ok" );

my $test_type_info = {
    'artistid' => {
        'data_type' => 'INT',
        'is_nullable' => 0,
        'size' => 11,
        'default_value' => undef,
    },
    'name' => {
        'data_type' => 'VARCHAR',
        'is_nullable' => 1,
        'size' => 100,
        'default_value' => undef,
    },
    'rank' => {
        'data_type' => 'INT',
        'is_nullable' => 0,
        'size' => 11,
        'default_value' => 13,
    },
    'charfield' => {
        'data_type' => 'CHAR',
        'is_nullable' => 1,
        'size' => 10,
        'default_value' => undef,
    },
};

$schema->populate ('Owners', [
  [qw/id  name  /],
  [qw/1   wiggle/],
  [qw/2   woggle/],
  [qw/3   boggle/],
]);

$schema->populate ('BooksInLibrary', [
  [qw/source  owner title   /],
  [qw/Library 1     secrets1/],
  [qw/Eatery  1     secrets2/],
  [qw/Library 2     secrets3/],
]);

#
# try a distinct + prefetch on tables with identically named columns 
# (mysql doesn't seem to like subqueries with equally named columns)
#

{
  # try a ->has_many direction (due to a 'multi' accessor the select/group_by group is collapsed)
  my $owners = $schema->resultset ('Owners')->search (
    { 'books.id' => { '!=', undef }},
    { prefetch => 'books', distinct => 1 }
  );
  my $owners2 = $schema->resultset ('Owners')->search ({ id => { -in => $owners->get_column ('me.id')->as_query }});
  for ($owners, $owners2) {
    is ($_->all, 2, 'Prefetched grouped search returns correct number of rows');
    is ($_->count, 2, 'Prefetched grouped search returns correct count');
  }

  # try a ->belongs_to direction (no select collapse)
  my $books = $schema->resultset ('BooksInLibrary')->search (
    { 'owner.name' => 'wiggle' },
    { prefetch => 'owner', distinct => 1 }
  );
  my $books2 = $schema->resultset ('BooksInLibrary')->search ({ id => { -in => $books->get_column ('me.id')->as_query }});
  for ($books, $books2) {
    is ($_->all, 1, 'Prefetched grouped search returns correct number of rows');
    is ($_->count, 1, 'Prefetched grouped search returns correct count');
  }
}

SKIP: {
    my $mysql_version = $dbh->get_info( $GetInfoType{SQL_DBMS_VER} );
    skip "Cannot determine MySQL server version", 1 if !$mysql_version;

    my ($v1, $v2, $v3) = $mysql_version =~ /^(\d+)\.(\d+)(?:\.(\d+))?/;
    skip "Cannot determine MySQL server version", 1 if !$v1 || !defined($v2);

    $v3 ||= 0;

    if( ($v1 < 5) || ($v1 == 5 && $v2 == 0 && $v3 <= 3) ) {
        $test_type_info->{charfield}->{data_type} = 'VARCHAR';
    }

    my $type_info = $schema->storage->columns_info_for('artist');
    is_deeply($type_info, $test_type_info, 'columns_info_for - column data types');
}

my $cd = $schema->resultset ('CD')->create ({});
my $producer = $schema->resultset ('Producer')->create ({});
lives_ok { $cd->set_producers ([ $producer ]) } 'set_relationship doesnt die';


## Can we properly deal with the null search problem?
##
## Only way is to do a SET SQL_AUTO_IS_NULL = 0; on connect
## But I'm not sure if we should do this or not (Ash, 2008/06/03)
#
# There is now a built-in function to do this, test that everything works
# with it (ribasushi, 2009/07/03)

NULLINSEARCH: {
    my $ansi_schema = DBICTest::Schema->connect ($dsn, $user, $pass, { on_connect_call => 'set_strict_mode' });

    $ansi_schema->resultset('Artist')->create ({ name => 'last created artist' });

    ok my $artist1_rs = $ansi_schema->resultset('Artist')->search({artistid=>6666})
      => 'Created an artist resultset of 6666';

    is $artist1_rs->count, 0
      => 'Got no returned rows';

    ok my $artist2_rs = $ansi_schema->resultset('Artist')->search({artistid=>undef})
      => 'Created an artist resultset of undef';

    is $artist2_rs->count, 0
      => 'got no rows';

    my $artist = $artist2_rs->single;

    is $artist => undef
      => 'Nothing Found!';
}

use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_ODBC_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 19;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

{
  no warnings 'redefine';
  my $connect_count = 0;
  my $orig_connect = \&DBI::connect;
  local *DBI::connect = sub { $connect_count++; goto &$orig_connect };

  $schema->storage->ensure_connected;

  is( $connect_count, 1, 'only one connection made');
}

isa_ok( $schema->storage, 'DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server' );

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

my %seen_id;

# fresh $schema so we start unconnected
$schema = DBICTest::Schema->connect($dsn, $user, $pass, {AutoCommit => 1});

# test primary key handling
my $new = $schema->resultset('Artist')->create({ name => 'foo' });
ok($new->artistid > 0, "Auto-PK worked");

$seen_id{$new->artistid}++;

# test LIMIT support
for (1..6) {
    $new = $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
    is ( $seen_id{$new->artistid}, undef, "id for Artist $_ is unique" );
    $seen_id{$new->artistid}++;
}

my $it = $schema->resultset('Artist')->search( {}, {
    rows => 3,
    order_by => 'artistid',
});

is( $it->count, 3, "LIMIT count ok" );
is( $it->next->name, "foo", "iterator->next ok" );
$it->next;
is( $it->next->name, "Artist 2", "iterator->next ok" );
is( $it->next, undef, "next past end of resultset ok" );

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { $dbh->do("DROP TABLE Owners") };
    eval { $dbh->do("DROP TABLE Books") };
    $dbh->do(<<'SQL');


CREATE TABLE Books (
   id INT IDENTITY (1, 1) NOT NULL,
   source VARCHAR(100),
   owner INT,
   title VARCHAR(10),
   price INT NULL
)

CREATE TABLE Owners (
   id INT IDENTITY (1, 1) NOT NULL,
   name VARCHAR(100),
)

SQL

});
$schema->populate ('Owners', [
  [qw/id  name  /],
  [qw/1   wiggle/],
  [qw/2   woggle/],
  [qw/3   boggle/],
  [qw/4   fREW/],
  [qw/5   fRIOUX/],
  [qw/6   fROOH/],
  [qw/7   fRUE/],
  [qw/8   fISMBoC/],
  [qw/9   station/],
  [qw/10   mirror/],
  [qw/11   dimly/],
  [qw/12   face_to_face/],
  [qw/13   icarus/],
  [qw/14   dream/],
  [qw/15   dyrstyggyr/],
]);

$schema->populate ('BooksInLibrary', [
  [qw/source  owner title   /],
  [qw/Library 1     secrets1/],
  [qw/Eatery  1     secrets2/],
  [qw/Library 2     secrets3/],
  [qw/Library 3     secrets4/],
  [qw/Eatery  3     secrets5/],
  [qw/Library 4     secrets6/],
  [qw/Library 5     secrets7/],
  [qw/Eatery  5     secrets8/],
  [qw/Library 6     secrets9/],
  [qw/Library 7     secrets10/],
  [qw/Eatery  7     secrets11/],
  [qw/Library 8     secrets12/],
]);

#
# try a distinct + prefetch on tables with identically named columns
#

{
  # try a ->has_many direction (group_by is not possible on has_many with limit)
  my $owners = $schema->resultset ('Owners')->search ({
      'books.id' => { '!=', undef }
    }, {
      prefetch => 'books',
      order_by => 'name',
      page     => 2,
      rows     => 4,
    });

  TODO: {
    local $TODO = 'limit past end of resultset problem';
    is ($owners->all, 3, 'has_many prefetch returns correct number of rows');
    is ($owners->count, 3, 'has-many prefetch returns correct count');
  }

  # try a ->belongs_to direction (no select collapse, group_by should work)
  my $books = $schema->resultset ('BooksInLibrary')->search ({
      'owner.name' => 'wiggle'
    }, {
      distinct => 1,
      prefetch => 'owner',
      order_by => 'name',
      rows     => 5,
    });


  is ($books->page(1)->all, 1, 'Prefetched grouped search returns correct number of rows');
  is ($books->page(1)->count, 1, 'Prefetched grouped search returns correct count');

  TODO: {
    local $TODO = 'limit past end of resultset problem';
    is ($books->page(2)->all, 0, 'Prefetched grouped search returns correct number of rows');
    is ($books->page(2)->count, 0, 'Prefetched grouped search returns correct count');
  }
}

# clean up our mess
END {
    my $dbh = eval { $schema->storage->_dbh };
    $dbh->do('DROP TABLE artist') if $dbh;
}
# vim:sw=2 sts=2

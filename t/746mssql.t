use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_ODBC_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_ODBC_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 39;

DBICTest::Schema->load_classes('ArtistGUID');
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

my @opts = (
  { on_connect_call => 'use_dynamic_cursors' },
  {},
);
my $new;

# test Auto-PK with different options
for my $opts (@opts) {
  SKIP: {
    $schema = DBICTest::Schema->connect($dsn, $user, $pass, $opts);

    eval {
      $schema->storage->ensure_connected
    };
    if ($@ =~ /dynamic cursors/) {
      skip
'Dynamic Cursors not functional, tds_version 8.0 or greater required if using'.
' FreeTDS', 1;
    }

    $schema->resultset('Artist')->search({ name => 'foo' })->delete;

    $new = $schema->resultset('Artist')->create({ name => 'foo' });

    ok($new->artistid > 0, "Auto-PK worked");
  }
}

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

# test GUID columns

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { $dbh->do("DROP TABLE artist") };
    $dbh->do(<<'SQL');
CREATE TABLE artist (
   artistid UNIQUEIDENTIFIER NOT NULL,
   name VARCHAR(100),
   rank INT NOT NULL DEFAULT '13',
   charfield CHAR(10) NULL,
   a_guid UNIQUEIDENTIFIER,
   primary key(artistid)
)
SQL
});

# start disconnected to make sure insert works on an un-reblessed storage
$schema = DBICTest::Schema->connect($dsn, $user, $pass);

my $row;
lives_ok {
  $row = $schema->resultset('ArtistGUID')->create({ name => 'mtfnpy' })
} 'created a row with a GUID';

ok(
  eval { $row->artistid },
  'row has GUID PK col populated',
);
diag $@ if $@;

ok(
  eval { $row->a_guid },
  'row has a GUID col with auto_nextval populated',
);
diag $@ if $@;

my $row_from_db = $schema->resultset('ArtistGUID')
  ->search({ name => 'mtfnpy' })->first;

is $row_from_db->artistid, $row->artistid,
  'PK GUID round trip';

is $row_from_db->a_guid, $row->a_guid,
  'NON-PK GUID round trip';

# test MONEY type
$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { $dbh->do("DROP TABLE money_test") };
    $dbh->do(<<'SQL');

CREATE TABLE money_test (
   id INT IDENTITY PRIMARY KEY,
   amount MONEY NULL
)

SQL

});

my $rs = $schema->resultset('Money');

lives_ok {
  $row = $rs->create({ amount => 100 });
} 'inserted a money value';

cmp_ok $rs->find($row->id)->amount, '==', 100, 'money value round-trip';

lives_ok {
  $row->update({ amount => 200 });
} 'updated a money value';

cmp_ok $rs->find($row->id)->amount, '==', 200,
  'updated money value round-trip';

lives_ok {
  $row->update({ amount => undef });
} 'updated a money value to NULL';

is $rs->find($row->id)->amount, undef,'updated money value to NULL round-trip';

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

lives_ok ( sub {
  # start a new connection, make sure rebless works
  my $schema = DBICTest::Schema->connect($dsn, $user, $pass);
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
}, 'populate with PKs supplied ok' );

lives_ok ( sub {
  # start a new connection, make sure rebless works
  my $schema = DBICTest::Schema->connect($dsn, $user, $pass);
  $schema->populate ('BooksInLibrary', [
    [qw/source  owner title   /],
    [qw/Library 1     secrets0/],
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
}, 'populate without PKs supplied ok' );

#
# try a prefetch on tables with identically named columns
#

# set quote char - make sure things work while quoted
$schema->storage->_sql_maker->{quote_char} = [qw/[ ]/];
$schema->storage->_sql_maker->{name_sep} = '.';

{
  # try a ->has_many direction
  my $owners = $schema->resultset ('Owners')->search ({
      'books.id' => { '!=', undef }
    }, {
      prefetch => 'books',
      order_by => 'name',
      rows     => 3,  # 8 results total
    });

  is ($owners->page(1)->all, 3, 'has_many prefetch returns correct number of rows');
  is ($owners->page(1)->count, 3, 'has-many prefetch returns correct count');

  TODO: {
    local $TODO = 'limit past end of resultset problem';
    is ($owners->page(3)->all, 2, 'has_many prefetch returns correct number of rows');
    is ($owners->page(3)->count, 2, 'has-many prefetch returns correct count');
    is ($owners->page(3)->count_rs->next, 2, 'has-many prefetch returns correct count_rs');

    # make sure count does not become overly complex
    is_same_sql_bind (
      $owners->page(3)->count_rs->as_query,
      '(
        SELECT COUNT( * )
          FROM (
            SELECT TOP 3 [me].[id]
              FROM [owners] [me]
              LEFT JOIN [books] [books] ON [books].[owner] = [me].[id]
            WHERE ( [books].[id] IS NOT NULL )
            GROUP BY [me].[id]
            ORDER BY [me].[id] DESC
          ) [count_subq]
      )',
      [],
    );
  }

  # try a ->belongs_to direction (no select collapse, group_by should work)
  my $books = $schema->resultset ('BooksInLibrary')->search ({
      'owner.name' => [qw/wiggle woggle/],
    }, {
      distinct => 1,
      prefetch => 'owner',
      rows     => 2,  # 3 results total
      order_by => { -desc => 'owner' },
      # there is no sane way to order by the right side of a grouped prefetch currently :(
      #order_by => { -desc => 'owner.name' },
    });


  is ($books->page(1)->all, 2, 'Prefetched grouped search returns correct number of rows');
  is ($books->page(1)->count, 2, 'Prefetched grouped search returns correct count');

  TODO: {
    local $TODO = 'limit past end of resultset problem';
    is ($books->page(2)->all, 1, 'Prefetched grouped search returns correct number of rows');
    is ($books->page(2)->count, 1, 'Prefetched grouped search returns correct count');
    is ($books->page(2)->count_rs->next, 1, 'Prefetched grouped search returns correct count_rs');

    # make sure count does not become overly complex (FIXME - the distinct-induced group_by is incorrect)
    is_same_sql_bind (
      $books->page(2)->count_rs->as_query,
      '(
        SELECT COUNT( * )
          FROM (
            SELECT TOP 2 [me].[id]
              FROM [books] [me]
              JOIN [owners] [owner] ON [owner].[id] = [me].[owner]
            WHERE ( ( ( [owner].[name] = ? OR [owner].[name] = ? ) AND [source] = ? ) )
            GROUP BY [me].[id], [me].[source], [me].[owner], [me].[title], [me].[price]
            ORDER BY [me].[id] DESC
          ) [count_subq]
      )',
      [
        [ 'owner.name' => 'wiggle' ],
        [ 'owner.name' => 'woggle' ],
        [ 'source' => 'Library' ],
      ],
    );
  }

}

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->_dbh }) {
    eval { $dbh->do("DROP TABLE $_") }
      for qw/artist money_test Books Owners/;
  }
}
# vim:sw=2 sts=2

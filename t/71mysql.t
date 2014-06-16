use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;

use DBI::Const::GetInfoType;
use Scalar::Util qw/weaken/;
use DBIx::Class::Optional::Dependencies ();

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_mysql')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_mysql');

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MYSQL_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MYSQL_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, { quote_names => 1 });

my $dbh = $schema->storage->dbh;

$dbh->do("DROP TABLE IF EXISTS artist;");

$dbh->do("CREATE TABLE artist (artistid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), rank INTEGER NOT NULL DEFAULT '13', charfield CHAR(10));");

$dbh->do("DROP TABLE IF EXISTS cd;");

$dbh->do("CREATE TABLE cd (cdid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, artist INTEGER, title TEXT, year DATE, genreid INTEGER, single_track INTEGER);");

$dbh->do("DROP TABLE IF EXISTS producer;");

$dbh->do("CREATE TABLE producer (producerid INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name TEXT);");

$dbh->do("DROP TABLE IF EXISTS cd_to_producer;");

$dbh->do("CREATE TABLE cd_to_producer (cd INTEGER,producer INTEGER);");

$dbh->do("DROP TABLE IF EXISTS owners;");

$dbh->do("CREATE TABLE owners (id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100) NOT NULL);");

$dbh->do("DROP TABLE IF EXISTS books;");

$dbh->do("CREATE TABLE books (id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY, source VARCHAR(100) NOT NULL, owner integer NOT NULL, title varchar(100) NOT NULL,  price integer);");

#'dbi:mysql:host=localhost;database=dbic_test', 'dbic_test', '');

# make sure sqlt_type overrides work (::Storage::DBI::mysql does this)
{
  my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

  ok (!$schema->storage->_dbh, 'definitely not connected');
  is ($schema->storage->sqlt_type, 'MySQL', 'sqlt_type correct pre-connection');
}

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

# Limit with select-lock
lives_ok {
  $schema->txn_do (sub {
    isa_ok (
      $schema->resultset('Artist')->find({artistid => 1}, {for => 'update', rows => 1}),
      'DBICTest::Schema::Artist',
    );
  });
} 'Limited FOR UPDATE select works';

# shared-lock
lives_ok {
  $schema->txn_do (sub {
    isa_ok (
      $schema->resultset('Artist')->find({artistid => 1}, {for => 'shared'}),
      'DBICTest::Schema::Artist',
    );
  });
} 'LOCK IN SHARE MODE select works';

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
    my $norm_version = $schema->storage->_server_info->{normalized_dbms_version}
      or skip "Cannot determine MySQL server version", 1;

    if ($norm_version < 5.000003_01) {
        $test_type_info->{charfield}->{data_type} = 'VARCHAR';
    }

    my $type_info = $schema->storage->columns_info_for('artist');
    is_deeply($type_info, $test_type_info, 'columns_info_for - column data types');
}

my $cd = $schema->resultset ('CD')->create ({});
my $producer = $schema->resultset ('Producer')->create ({});
lives_ok { $cd->set_producers ([ $producer ]) } 'set_relationship doesnt die';

{
  my $artist = $schema->resultset('Artist')->next;
  my $cd = $schema->resultset('CD')->next;
  $cd->set_from_related ('artist', $artist);
  $cd->update;

  my $rs = $schema->resultset('CD')->search ({}, { prefetch => 'artist' });

  lives_ok sub {
    my $cd = $rs->next;
    is ($cd->artist->name, $artist->name, 'Prefetched artist');
  }, 'join does not throw (mysql 3 test)';

  # induce a jointype override, make sure it works even if we don't have mysql3
  local $schema->storage->sql_maker->{_default_jointype} = 'inner';
  is_same_sql_bind (
    $rs->as_query,
    '(
      SELECT `me`.`cdid`, `me`.`artist`, `me`.`title`, `me`.`year`, `me`.`genreid`, `me`.`single_track`,
             `artist`.`artistid`, `artist`.`name`, `artist`.`rank`, `artist`.`charfield`
        FROM cd `me`
        INNER JOIN `artist` `artist` ON `artist`.`artistid` = `me`.`artist`
    )',
    [],
    'overridden default join type works',
  );
}

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

    is $artist => undef,
      => 'Nothing Found!';
}

# check for proper grouped counts
{
  my $ansi_schema = DBICTest::Schema->connect ($dsn, $user, $pass, {
    on_connect_call => 'set_strict_mode',
    quote_char => '`',
  });
  my $rs = $ansi_schema->resultset('CD');

  my $years;
  $years->{$_->year|| scalar keys %$years}++ for $rs->all;  # NULL != NULL, thus the keys eval

  lives_ok ( sub {
    is (
      $rs->search ({}, { group_by => 'year'})->count,
      scalar keys %$years,
      'grouped count correct',
    );
  }, 'Grouped count does not throw');

  lives_ok( sub {
    $ansi_schema->resultset('Owners')->search({}, {
      join => 'books', group_by => [ 'me.id', 'books.id' ]
    })->count();
  }, 'count on grouped columns with the same name does not throw');
}

# a more contrived^Wcomplicated self-referential double-subquery test
{
  my $rs = $schema->resultset('Artist')->search({ name => { -like => 'baby_%' } });

  $rs->populate([map { [$_] } ('name', map { "baby_$_" } (1..10) ) ]);

  my ($count_sql, @count_bind) = @${$rs->count_rs->as_query};

  my $complex_rs = $schema->resultset('Artist')->search(
    { artistid => {
      -in => $rs->get_column('artistid')
                  ->as_query
    } },
  );

  $complex_rs->update({ name => \[ "CONCAT( `name`, '_bell_out_of_', $count_sql )", @count_bind ] });

  for (1..10) {
    is (
      $schema->resultset('Artist')->search({ name => "baby_${_}_bell_out_of_10" })->count,
      1,
      "Correctly updated babybell $_",
    );
  }

  is ($rs->count, 10, '10 artists present');

  my $orig_debug = $schema->storage->debug;
  $schema->storage->debug(1);
  my $query_count;
  $schema->storage->debugcb(sub { $query_count++ });

  $query_count = 0;
  $complex_rs->delete;

  is ($query_count, 1, 'One delete query fired');
  is ($rs->count, 0, '10 Artists correctly deleted');

  $rs->create({
    name => 'baby_with_cd',
    cds => [ { title => 'babeeeeee', year => 2013 } ],
  });
  is ($rs->count, 1, 'Artist with cd created');

  $query_count = 0;
  $schema->resultset('CD')->search_related('artist',
    { 'artist.name' => { -like => 'baby_with_%' } }
  )->delete;
  is ($query_count, 1, 'And one more delete query fired');
  is ($rs->count, 0, 'Artist with cd deleted');

  $schema->storage->debugcb(undef);
  $schema->storage->debug($orig_debug);
}

ZEROINSEARCH: {
  my $cds_per_year = {
    2001 => 2,
    2002 => 1,
    2005 => 3,
  };

  my $rs = $schema->resultset ('CD');
  $rs->delete;
  for my $y (keys %$cds_per_year) {
    for my $c (1 .. $cds_per_year->{$y} ) {
      $rs->create ({ title => "CD $y-$c", artist => 1, year => "$y-01-01" });
    }
  }

  is ($rs->count, 6, 'CDs created successfully');

  $rs = $rs->search ({}, {
    select => [ \ 'YEAR(year)' ], as => ['y'], distinct => 1,
  });

  my $y_rs = $rs->get_column ('y');

  warnings_exist { is_deeply (
    [ sort ($y_rs->all) ],
    [ sort keys %$cds_per_year ],
    'Years group successfully',
  ) } qr/
    \QUse of distinct => 1 while selecting anything other than a column \E
    \Qdeclared on the primary ResultSource is deprecated\E
  /x, 'deprecation warning';


  $rs->create ({ artist => 1, year => '0-1-1', title => 'Jesus Rap' });

  is_deeply (
    [ sort $y_rs->all ],
    [ 0, sort keys %$cds_per_year ],
    'Zero-year groups successfully',
  );

  # convoluted search taken verbatim from list
  my $restrict_rs = $rs->search({ -and => [
    year => { '!=', 0 },
    year => { '!=', undef }
  ]});

  warnings_exist { is_deeply (
    [ $restrict_rs->get_column('y')->all ],
    [ $y_rs->all ],
    'Zero year was correctly excluded from resultset',
  ) } qr/
    \QUse of distinct => 1 while selecting anything other than a column \E
    \Qdeclared on the primary ResultSource is deprecated\E
  /x, 'deprecation warning';
}

# make sure find hooks determine driver
{
  my $schema = DBICTest::Schema->connect($dsn, $user, $pass);
  $schema->resultset("Artist")->find(4);
  isa_ok($schema->storage->sql_maker, 'DBIx::Class::SQLMaker::MySQL');
}

# make sure the mysql_auto_reconnect buggery is avoided
{
  local $ENV{MOD_PERL} = 'boogiewoogie';
  my $schema = DBICTest::Schema->connect($dsn, $user, $pass);
  ok (! $schema->storage->_get_dbh->{mysql_auto_reconnect}, 'mysql_auto_reconnect unset regardless of ENV' );

  # Make sure hardcore forking action still works even if mysql_auto_reconnect
  # is true (test inspired by ether)

  my $schema_autorecon = DBICTest::Schema->connect($dsn, $user, $pass, { mysql_auto_reconnect => 1 });
  my $orig_dbh = $schema_autorecon->storage->_get_dbh;
  weaken $orig_dbh;

  ok ($orig_dbh, 'Got weak $dbh ref');
  ok ($orig_dbh->{mysql_auto_reconnect}, 'mysql_auto_reconnect is properly set if explicitly requested' );

  my $rs = $schema_autorecon->resultset('Artist');

  my ($parent_in, $child_out);
  pipe( $parent_in, $child_out ) or die "Pipe open failed: $!";
  my $pid = fork();
  if (! defined $pid ) {
    die "fork() failed: $!"
  }
  elsif ($pid) {
    close $child_out;

    # sanity check
    $schema_autorecon->storage->dbh_do(sub {
      is ($_[1], $orig_dbh, 'Storage holds correct $dbh in parent');
    });

    # kill our $dbh
    $schema_autorecon->storage->_dbh(undef);

    {
      local $TODO = "Perl $] is known to leak like a sieve"
        if DBIx::Class::_ENV_::PEEPEENESS;

      ok (! defined $orig_dbh, 'Parent $dbh handle is gone');
    }
  }
  else {
    close $parent_in;

    #simulate a  subtest to not confuse the parent TAP emission
    my $tb = Test::More->builder;
    $tb->reset;
    for (qw/output failure_output todo_output/) {
      close $tb->$_;
      open ($tb->$_, '>&', $child_out);
    }

    # wait for parent to kill its $dbh
    sleep 1;

    # try to do something dbic-esque
    $rs->create({ name => "Hardcore Forker $$" });

    {
      local $TODO = "Perl $] is known to leak like a sieve"
        if DBIx::Class::_ENV_::PEEPEENESS;

      ok (! defined $orig_dbh, 'DBIC operation triggered reconnect - old $dbh is gone');
    }

    done_testing;
    exit 0;
  }

  while (my $ln = <$parent_in>) {
    print "   $ln";
  }
  wait;
  ok(!$?, 'Child subtests passed');

  ok ($rs->find({ name => "Hardcore Forker $pid" }), 'Expected row created');
}

done_testing;

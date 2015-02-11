use strict;
use warnings;

use Test::More;
use Test::Exception;
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for ('test_rdbms_mssql_ado')
  unless DBIx::Class::Optional::Dependencies->req_ok_for ('test_rdbms_mssql_ado');

# Example DSN (from frew):
# dbi:ADO:PROVIDER=sqlncli10;SERVER=tcp:172.24.2.10;MARS Connection=True;Initial Catalog=CIS;UID=cis_web;PWD=...;DataTypeCompatibility=80;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_MSSQL_ADO_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_MSSQL_ADO_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

DBICTest::Schema->load_classes(qw/VaryingMAX ArtistGUID/);

my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
$binstr{'large'} = $binstr{'small'} x 1024;

my $maxloblen = length $binstr{'large'};

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
  auto_savepoint => 1,
  LongReadLen => $maxloblen,
});

$schema->storage->ensure_connected;

isa_ok($schema->storage, 'DBIx::Class::Storage::DBI::ADO::Microsoft_SQL_Server');

my $ver = $schema->storage->_server_info->{normalized_dbms_version};

ok $ver, 'can introspect DBMS version';

# 2005 and greater
is $schema->storage->sql_limit_dialect, ($ver >= 9 ? 'RowNumberOver' : 'Top'),
  'correct limit dialect detected';

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    try { local $^W = 0; $dbh->do("DROP TABLE artist") };
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

$schema->storage->dbh_do (sub {
  my ($storage, $dbh) = @_;
  try { local $^W = 0; $dbh->do("DROP TABLE artist_guid") };
  $dbh->do(<<"SQL");
CREATE TABLE artist_guid (
 artistid UNIQUEIDENTIFIER NOT NULL,
 name VARCHAR(100),
 rank INT NULL,
 charfield CHAR(10) NULL,
 a_guid UNIQUEIDENTIFIER,
 primary key(artistid)
)
SQL
});

my $have_max = $ver >= 9; # 2005 and greater

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    try { local $^W = 0; $dbh->do("DROP TABLE varying_max_test") };
    $dbh->do("
CREATE TABLE varying_max_test (
   id INT IDENTITY NOT NULL,
" . ($have_max ? "
   varchar_max VARCHAR(MAX),
   nvarchar_max NVARCHAR(MAX),
   varbinary_max VARBINARY(MAX),
" : "
   varchar_max TEXT,
   nvarchar_max NTEXT,
   varbinary_max IMAGE,
") . "
   primary key(id)
)");
});

my $ars = $schema->resultset('Artist');

my $new = $ars->create({ name => 'foo' });
ok($new->artistid > 0, 'Auto-PK worked');

# make sure select works
my $found = $schema->resultset('Artist')->search({ name => 'foo' })->first;
is $found->artistid, $new->artistid, 'search works';

# test large column list in select
$found = $schema->resultset('Artist')->search({ name => 'foo' }, {
  select => ['artistid', 'name', map \"'foo' foo_$_", 0..50],
  as     => ['artistid', 'name', map        "foo_$_", 0..50],
})->first;
is $found->artistid, $new->artistid, 'select with big column list';
is $found->get_column('foo_50'), 'foo', 'last item in big column list';

# create a few more rows
for (1..12) {
  $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}

# test multiple active cursors
my $rs1 = $schema->resultset('Artist')->search({}, { order_by => 'artistid' });
my $rs2 = $schema->resultset('Artist')->search({}, { order_by => 'name' });

while ($rs1->next) {
  ok try { $rs2->next }, 'multiple active cursors';
}

# test bug where ADO blows up if the first bindparam is shorter than the second
is $schema->resultset('Artist')->search({ artistid => 2 })->first->name,
  'Artist 1',
  'short bindparam';

is $schema->resultset('Artist')->search({ artistid => 13 })->first->name,
  'Artist 12',
  'longer bindparam';

# test explicit key spec
$new = $ars->create ({ name => 'bar', artistid => 66 });
is($new->artistid, 66, 'Explicit PK worked');
$new->discard_changes;
is($new->artistid, 66, 'Explicit PK assigned');

# test basic transactions
$schema->txn_do(sub {
  $ars->create({ name => 'transaction_commit' });
});
ok($ars->search({ name => 'transaction_commit' })->first,
  'transaction committed');
$ars->search({ name => 'transaction_commit' })->delete,
throws_ok {
  $schema->txn_do(sub {
    $ars->create({ name => 'transaction_rollback' });
    die 'rolling back';
  });
} qr/rolling back/, 'rollback executed';
is $ars->search({ name => 'transaction_rollback' })->first, undef,
  'transaction rolled back';

# test two-phase commit and inner transaction rollback from nested transactions
$schema->txn_do(sub {
  $ars->create({ name => 'in_outer_transaction' });
  $schema->txn_do(sub {
    $ars->create({ name => 'in_inner_transaction' });
  });
  ok($ars->search({ name => 'in_inner_transaction' })->first,
    'commit from inner transaction visible in outer transaction');
  throws_ok {
    $schema->txn_do(sub {
      $ars->create({ name => 'in_inner_transaction_rolling_back' });
      die 'rolling back inner transaction';
    });
  } qr/rolling back inner transaction/, 'inner transaction rollback executed';
});
ok($ars->search({ name => 'in_outer_transaction' })->first,
  'commit from outer transaction');
ok($ars->search({ name => 'in_inner_transaction' })->first,
  'commit from inner transaction');
is $ars->search({ name => 'in_inner_transaction_rolling_back' })->first,
  undef,
  'rollback from inner transaction';
$ars->search({ name => 'in_outer_transaction' })->delete;
$ars->search({ name => 'in_inner_transaction' })->delete;

# test populate
lives_ok (sub {
  my @pop;
  for (1..2) {
    push @pop, { name => "Artist_$_" };
  }
  $ars->populate (\@pop);
});

# test populate with explicit key
lives_ok (sub {
  my @pop;
  for (1..2) {
    push @pop, { name => "Artist_expkey_$_", artistid => 100 + $_ };
  }
  $ars->populate (\@pop);
});

# count what we did so far
is ($ars->count, 18, 'Simple count works');

# test empty insert
my $current_artistid = $ars->search({}, {
  select => [ { max => 'artistid' } ], as => ['artistid']
})->first->artistid;

my $row;
lives_ok { $row = $ars->create({}) }
  'empty insert works';

$row->discard_changes;

is $row->artistid, $current_artistid+1,
  'empty insert generated correct PK';

# test that autoinc column still works after empty insert
  $row = $ars->create({ name => 'after_empty_insert' });

  is $row->artistid, $current_artistid+2,
    'autoincrement column functional aftear empty insert';

my $rs = $schema->resultset('VaryingMAX');

foreach my $size (qw/small large/) {
  local $schema->storage->{debug} = 0 if $size eq 'large';

  my $str = $binstr{$size};
  my $row;
  lives_ok {
    $row = $rs->create({
      varchar_max => $str, nvarchar_max => $str, varbinary_max => $str
    });
  } "created $size VARXXX(MAX) LOBs";

  lives_ok {
    $row->discard_changes;
  } 're-selected just-inserted LOBs';

  cmp_ok try { $row->varchar_max },   'eq', $str, 'VARCHAR(MAX) matches';
  cmp_ok try { $row->nvarchar_max },  'eq', $str, 'NVARCHAR(MAX) matches';
  cmp_ok try { $row->varbinary_max }, 'eq', $str, 'VARBINARY(MAX) matches';
}

# test regular blobs

try { local $^W = 0; $schema->storage->dbh->do('DROP TABLE bindtype_test') };
$schema->storage->dbh->do(qq[
CREATE TABLE bindtype_test
(
  id     INT IDENTITY NOT NULL PRIMARY KEY,
  bytea  INT NULL,
  blob   IMAGE NULL,
  clob   TEXT NULL,
  a_memo NTEXT NULL
)
],{ RaiseError => 1, PrintError => 1 });

$rs = $schema->resultset('BindType');
my $id = 0;

foreach my $type (qw( blob clob a_memo )) {
  foreach my $size (qw( small large )) {
    $id++;

    lives_ok { $rs->create( { 'id' => $id, $type => $binstr{$size} } ) }
      "inserted $size $type without dying" or next;

    my $from_db = eval { $rs->find($id)->$type } || '';
    diag $@ if $@;

    ok($from_db eq $binstr{$size}, "verified inserted $size $type" )
      or do {
        my $hexdump = sub {
          join '', map sprintf('%02X', ord), split //, shift
        };
        diag 'Got: ', "\n", substr($hexdump->($from_db),0,255), '...',
          substr($hexdump->($from_db),-255);
        diag 'Size: ', length($from_db);
        diag 'Expected Size: ', length($binstr{$size});
        diag 'Expected: ', "\n",
          substr($hexdump->($binstr{$size}), 0, 255),
          "...", substr($hexdump->($binstr{$size}),-255);
      };
  }
}
# test IMAGE update
lives_ok {
  $rs->search({ id => 0 })->update({ blob => $binstr{small} });
} 'updated IMAGE to small binstr without dying';

lives_ok {
  $rs->search({ id => 0 })->update({ blob => $binstr{large} });
} 'updated IMAGE to large binstr without dying';

# test GUIDs
lives_ok {
  $row = $schema->resultset('ArtistGUID')->create({ name => 'mtfnpy' })
} 'created a row with a GUID';

ok(
  eval { $row->artistid },
  'row has GUID PK col populated',
);
diag $@ if $@;

my $guid = try { $row->artistid }||'';

ok(($guid !~ /^{.*?}\z/), 'GUID not enclosed in braces')
  or diag "GUID is: $guid";

ok(
  eval { $row->a_guid },
  'row has a GUID col with auto_nextval populated',
);
diag $@ if $@;

my $row_from_db = $schema->resultset('ArtistGUID')
  ->search({ name => 'mtfnpy' })->first;

is try { $row_from_db->artistid }, try { $row->artistid },
  'PK GUID round trip (via ->search->next)';

is try { $row_from_db->a_guid }, try { $row->a_guid },
  'NON-PK GUID round trip (via ->search->next)';

$row_from_db = try { $schema->resultset('ArtistGUID')
  ->find($row->artistid) };

is try { $row_from_db->artistid }, try { $row->artistid },
  'PK GUID round trip (via ->find)';

is try { $row_from_db->a_guid }, try { $row->a_guid },
  'NON-PK GUID round trip (via ->find)';

($row_from_db) = $schema->resultset('ArtistGUID')
  ->search({ name => 'mtfnpy' })->all;

is try { $row_from_db->artistid }, try { $row->artistid },
  'PK GUID round trip (via ->search->all)';

is try { $row_from_db->a_guid }, try { $row->a_guid },
  'NON-PK GUID round trip (via ->search->all)';

lives_ok {
  $row = $schema->resultset('ArtistGUID')->create({
      artistid => '70171270-4822-4450-81DF-921F99BA3C06',
      name => 'explicit_guid',
  });
} 'created a row with explicit PK GUID';

is try { $row->artistid }, '70171270-4822-4450-81DF-921F99BA3C06',
  'row has correct PK GUID';

lives_ok {
  $row->update({ artistid => '70171270-4822-4450-81DF-921F99BA3C07' });
} "updated row's PK GUID";

is try { $row->artistid }, '70171270-4822-4450-81DF-921F99BA3C07',
  'row has correct PK GUID';

lives_ok {
  $row->delete;
} 'deleted the row';

lives_ok {
  $schema->resultset('ArtistGUID')->populate([{
      artistid => '70171270-4822-4450-81DF-921F99BA3C06',
      name => 'explicit_guid',
  }]);
} 'created a row with explicit PK GUID via ->populate in void context';

done_testing;

# clean up our mess
END {
  local $SIG{__WARN__} = sub {};
  if (my $dbh = try { $schema->storage->_dbh }) {
    (try { $dbh->do("DROP TABLE $_") })
      for qw/artist artist_guid varying_max_test bindtype_test/;
  }

  undef $schema;
}
# vim:sw=2 sts=2

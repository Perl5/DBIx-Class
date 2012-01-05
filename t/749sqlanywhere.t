use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass)    = @ENV{map { "DBICTEST_SQLANYWHERE_${_}" }      qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_SQLANYWHERE_ODBC_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Test needs ' .
  (join ' or ', map { $_ ? $_ : () }
    DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_sqlanywhere'),
    DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_sqlanywhere_odbc'))
  unless
    $dsn && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_sqlanywhere')
    or
    $dsn2 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_sqlanywhere_odbc')
    or
    (not $dsn || $dsn2);

DBICTest::Schema->load_classes('ArtistGUID');

# tests stolen from 748informix.t

plan skip_all => <<'EOF' unless $dsn || $dsn2;
Set $ENV{DBICTEST_SQLANYWHERE_DSN} and/or $ENV{DBICTEST_SQLANYWHERE_ODBC_DSN},
_USER and _PASS to run these tests
EOF

my @info = (
  [ $dsn,  $user,  $pass  ],
  [ $dsn2, $user2, $pass2 ],
);

my $schema;

foreach my $info (@info) {
  my ($dsn, $user, $pass) = @$info;

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    auto_savepoint => 1
  });

  my $guard = Scope::Guard->new(\&cleanup);

  my $dbh = $schema->storage->dbh;

  eval { $dbh->do("DROP TABLE artist") };

  $dbh->do(<<EOF);
  CREATE TABLE artist (
    artistid INT IDENTITY PRIMARY KEY,
    name VARCHAR(255) NULL,
    charfield CHAR(10) NULL,
    rank INT DEFAULT 13
  )
EOF

  my $ars = $schema->resultset('Artist');
  is ( $ars->count, 0, 'No rows at first' );

# test primary key handling
  my $new = $ars->create({ name => 'foo' });
  ok($new->artistid, "Auto-PK worked");

# test explicit key spec
  $new = $ars->create ({ name => 'bar', artistid => 66 });
  is($new->artistid, 66, 'Explicit PK worked');
  $new->discard_changes;
  is($new->artistid, 66, 'Explicit PK assigned');

# test savepoints
  throws_ok {
    $schema->txn_do(sub {
      eval {
        $schema->txn_do(sub {
          $ars->create({ name => 'in_savepoint' });
          die "rolling back savepoint";
        });
      };
      ok ((not $ars->search({ name => 'in_savepoint' })->first),
        'savepoint rolled back');
      $ars->create({ name => 'in_outer_txn' });
      die "rolling back outer txn";
    });
  } qr/rolling back outer txn/,
    'correct exception for rollback';

  ok ((not $ars->search({ name => 'in_outer_txn' })->first),
    'outer txn rolled back');

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
  is ($ars->count, 6, 'Simple count works');

# test LIMIT support
  my $lim = $ars->search( {},
    {
      rows => 3,
      offset => 4,
      order_by => 'artistid'
    }
  );
  is( $lim->count, 2, 'ROWS+OFFSET count ok' );
  is( $lim->all, 2, 'Number of ->all objects matches count' );

# test iterator
  $lim->reset;
  is( $lim->next->artistid, 101, "iterator->next ok" );
  is( $lim->next->artistid, 102, "iterator->next ok" );
  is( $lim->next, undef, "next past end of resultset ok" );

# test empty insert
  {
    local $ars->result_source->column_info('artistid')->{is_auto_increment} = 0;

    lives_ok { $ars->create({}) }
      'empty insert works';
  }

# test blobs (stolen from 73oracle.t)
  eval { $dbh->do('DROP TABLE bindtype_test') };
  $dbh->do(qq[
  CREATE TABLE bindtype_test
  (
    id     INT          NOT NULL PRIMARY KEY,
    bytea  INT          NULL,
    blob   LONG BINARY  NULL,
    clob   LONG VARCHAR NULL,
    a_memo INT          NULL
  )
  ],{ RaiseError => 1, PrintError => 1 });

  my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
  $binstr{'large'} = $binstr{'small'} x 1024;

  my $maxloblen = length $binstr{'large'};
  local $dbh->{'LongReadLen'} = $maxloblen;

  my $rs = $schema->resultset('BindType');
  my $id = 0;

  foreach my $type (qw( blob clob )) {
    foreach my $size (qw( small large )) {
      $id++;

# turn off horrendous binary DBIC_TRACE output
      local $schema->storage->{debug} = 0;

      lives_ok { $rs->create( { 'id' => $id, $type => $binstr{$size} } ) }
      "inserted $size $type without dying";

      ok($rs->find($id)->$type eq $binstr{$size}, "verified inserted $size $type" );
    }
  }

  my @uuid_types = qw/uniqueidentifier uniqueidentifierstr/;

# test uniqueidentifiers (and the cursor_class).

  for my $uuid_type (@uuid_types) {
    local $schema->source('ArtistGUID')->column_info('artistid')->{data_type}
      = $uuid_type;

    local $schema->source('ArtistGUID')->column_info('a_guid')->{data_type}
      = $uuid_type;

    $schema->storage->dbh_do (sub {
      my ($storage, $dbh) = @_;
      eval { $dbh->do("DROP TABLE artist_guid") };
      $dbh->do(<<"SQL");
CREATE TABLE artist_guid (
   artistid $uuid_type NOT NULL,
   name VARCHAR(100),
   rank INT NOT NULL DEFAULT '13',
   charfield CHAR(10) NULL,
   a_guid $uuid_type,
   primary key(artistid)
)
SQL
    });

    local $TODO = 'something wrong with uniqueidentifierstr over ODBC'
      if $dsn =~ /:ODBC:/ && $uuid_type eq 'uniqueidentifierstr';

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

    my $row_from_db = try { $schema->resultset('ArtistGUID')
      ->search({ name => 'mtfnpy' })->first }
      catch { diag $_ };

    is try { $row_from_db->artistid }, $row->artistid,
      'PK GUID round trip (via ->search->next)';

    is try { $row_from_db->a_guid }, $row->a_guid,
      'NON-PK GUID round trip (via ->search->next)';

    $row_from_db = try { $schema->resultset('ArtistGUID')
      ->find($row->artistid) }
      catch { diag $_ };

    is try { $row_from_db->artistid }, $row->artistid,
      'PK GUID round trip (via ->find)';

    is try { $row_from_db->a_guid }, $row->a_guid,
      'NON-PK GUID round trip (via ->find)';

    ($row_from_db) = try { $schema->resultset('ArtistGUID')
      ->search({ name => 'mtfnpy' })->all }
      catch { diag $_ };

    is try { $row_from_db->artistid }, $row->artistid,
      'PK GUID round trip (via ->search->all)';

    is try { $row_from_db->a_guid }, $row->a_guid,
      'NON-PK GUID round trip (via ->search->all)';
  }
}

done_testing;

sub cleanup {
  eval { $schema->storage->dbh->do("DROP TABLE $_") }
    for qw/artist artist_guid bindtype_test/;
}

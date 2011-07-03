use strict;
use warnings;

use Test::More;
use Test::Exception;
use Scope::Guard ();
use Try::Tiny;
use DBIx::Class::Optional::Dependencies ();
use lib qw(t/lib);
use DBICTest;
use DBIC::DebugObj ();
use DBIC::SqlMakerTest;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_MSACCESS_ODBC_${_}" } qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_MSACCESS_ADO_${_}" }  qw/DSN USER PASS/};

plan skip_all => 'Test needs ' .
  (join ' or ', map { $_ ? $_ : () }
    DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_msaccess_odbc'),
    DBIx::Class::Optional::Dependencies->req_missing_for('test_rdbms_msaccess_ado'))
  unless
    $dsn && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_msaccess_odbc')
    or
    $dsn2 && DBIx::Class::Optional::Dependencies->req_ok_for('test_rdbms_msaccess_ado')
    or
    (not $dsn || $dsn2);

DBICTest::Schema->load_classes('ArtistGUID');

# Example DSNs (32bit only):
# dbi:ODBC:driver={Microsoft Access Driver (*.mdb, *.accdb)};dbq=C:\Users\rkitover\Documents\access_sample.accdb
# dbi:ADO:Microsoft.Jet.OLEDB.4.0;Data Source=C:\Users\rkitover\Documents\access_sample.accdb
# dbi:ADO:Provider=Microsoft.ACE.OLEDB.12.0;Data Source=C:\Users\rkitover\Documents\access_sample.accdb;Persist Security Info=False'

plan skip_all => <<'EOF' unless $dsn || $dsn2;
Set $ENV{DBICTEST_MSACCESS_ODBC_DSN} and/or $ENV{DBICTEST_MSACCESS_ADO_DSN} (and optionally _USER and _PASS) to run these tests.
Warning: this test drops and creates the tables 'artist', 'cd', 'bindtype_test' and 'artist_guid'.
EOF

my @info = (
  [ $dsn,  $user  || '', $pass  || '' ],
  [ $dsn2, $user2 || '', $pass2 || '' ],
);

my $schema;

foreach my $info (@info) {
  my ($dsn, $user, $pass) = @$info;

  next unless $dsn;

# Check that we can connect without any options.
  $schema = DBICTest::Schema->connect($dsn, $user, $pass);
  lives_ok {
    $schema->storage->ensure_connected;
  } 'connection without any options';

  my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
  $binstr{'large'} = $binstr{'small'} x 1024;

  my $maxloblen = length $binstr{'large'};

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    quote_names => 1,
    auto_savepoint => 1,
    LongReadLen => $maxloblen,
  });

  my $guard = Scope::Guard->new(\&cleanup);

  my $dbh = $schema->storage->dbh;

  # turn off warnings for OLE exception from ADO about nonexistant table
  eval { local $^W = 0; $dbh->do("DROP TABLE artist") };

  $dbh->do(<<EOF);
  CREATE TABLE artist (
    artistid AUTOINCREMENT PRIMARY KEY,
    name VARCHAR(255) NULL,
    charfield CHAR(10) NULL,
    rank INT NULL
  )
EOF

  my $ars = $schema->resultset('Artist');
  is ( $ars->count, 0, 'No rows at first' );

# test primary key handling
  my $new = $ars->create({ name => 'foo' });
  ok($new->artistid, "Auto-PK worked");

  my $first_artistid = $new->artistid;

# test explicit key spec
  $new = $ars->create ({ name => 'bar', artistid => 66 });
  is($new->artistid, 66, 'Explicit PK worked');
  $new->discard_changes;
  is($new->artistid, 66, 'Explicit PK assigned');

# test joins
  eval { local $^W = 0; $dbh->do("DROP TABLE cd") };

  $dbh->do(<<EOF);
  CREATE TABLE cd (
    cdid AUTOINCREMENT PRIMARY KEY,
    artist INTEGER NULL,
    title VARCHAR(255) NULL,
    [year] CHAR(4) NULL,
    genreid INTEGER NULL,
    single_track INTEGER NULL
  )
EOF

  $dbh->do(<<EOF);
  CREATE TABLE track (
    trackid AUTOINCREMENT PRIMARY KEY,
    cd INTEGER REFERENCES cd(cdid),
    [position] INTEGER,
    title VARCHAR(255),
    last_updated_on DATETIME,
    last_updated_at DATETIME
  )
EOF

  my $cd = $schema->resultset('CD')->create({
    artist => $first_artistid,
    title => 'Some Album',
  });

# one-step join
  my $joined_artist = $schema->resultset('Artist')->search({
    artistid => $first_artistid,
  }, {
    join => [ 'cds' ],
    '+select' => [ 'cds.title' ],
    '+as'     => [ 'cd_title'  ],
  })->next;

  is $joined_artist->get_column('cd_title'), 'Some Album',
    'one-step join works';

# two-step join
  my $track = $schema->resultset('Track')->create({
    cd => $cd->cdid,
    position => 1,
    title => 'my track',
  });

  my ($sql, @bind);

  my $joined_track = try {
    local $schema->storage->{debug} = 1;
    local $schema->storage->{debugobj} = DBIC::DebugObj->new(\$sql, \@bind);

    $schema->resultset('Artist')->search({
      artistid => $first_artistid,
    }, {
      join => [{ cds => 'tracks' }],
      '+select' => [ 'tracks.title' ],
      '+as'     => [ 'track_title'  ],
    })->next;
  }
  catch {
    diag "Could not execute two-step left join: $_";
  };

  s/^'//, s/'\z// for @bind;

  is_same_sql_bind(
    $sql,
    \@bind,
    'SELECT [me].[artistid], [me].[name], [me].[rank], [me].[charfield], [tracks].[title] FROM ( ( [artist] [me] LEFT JOIN cd [cds] ON [cds].[artist] = [me].[artistid] ) LEFT JOIN [track] [tracks] ON [tracks].[cd] = [cds].[cdid] ) WHERE ( [artistid] = ? )',
    [1],
    'correct SQL for two-step left join',
  );

  is try { $joined_track->get_column('track_title') }, 'my track',
    'two-step left join works';

  ($sql, @bind) = ();

  $joined_artist = try {
    local $schema->storage->{debug} = 1;
    local $schema->storage->{debugobj} = DBIC::DebugObj->new(\$sql, \@bind);

    $schema->resultset('Track')->search({
      trackid => $track->trackid,
    }, {
      join => [{ cd => 'artist' }],
      '+select' => [ 'artist.name' ],
      '+as'     => [ 'artist_name'  ],
    })->next;
  }
  catch {
    diag "Could not execute two-step inner join: $_";
  };

  s/^'//, s/'\z// for @bind;

  is_same_sql_bind(
    $sql,
    \@bind,
    'SELECT [me].[trackid], [me].[cd], [me].[position], [me].[title], [me].[last_updated_on], [me].[last_updated_at], [artist].[name] FROM ( ( [track] [me] INNER JOIN cd [cd] ON [cd].[cdid] = [me].[cd] ) INNER JOIN [artist] [artist] ON [artist].[artistid] = [cd].[artist] ) WHERE ( [trackid] = ? )',
    [$track->trackid],
    'correct SQL for two-step inner join',
  );

  is try { $joined_artist->get_column('artist_name') }, 'foo',
    'two-step inner join works';

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
  is ($ars->count, 6, 'Simple count works');

# test LIMIT support
# not testing offset because access only supports TOP
  my $lim = $ars->search( {},
    {
      rows => 2,
      offset => 0,
      order_by => 'artistid'
    }
  );
  is( $lim->count, 2, 'ROWS+OFFSET count ok' );
  is( $lim->all, 2, 'Number of ->all objects matches count' );

# test iterator
  $lim->reset;
  is( $lim->next->artistid, 1, "iterator->next ok" );
  is( $lim->next->artistid, 66, "iterator->next ok" );
  is( $lim->next, undef, "next past end of resultset ok" );

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

# test blobs (stolen from 73oracle.t)

# turn off horrendous binary DBIC_TRACE output
  {
    local $schema->storage->{debug} = 0;

    eval { local $^W = 0; $dbh->do('DROP TABLE bindtype_test') };
    $dbh->do(qq[
    CREATE TABLE bindtype_test
    (
      id     INT          NOT NULL PRIMARY KEY,
      bytea  INT          NULL,
      blob   IMAGE        NULL,
      clob   TEXT         NULL,
      a_memo MEMO         NULL
    )
    ],{ RaiseError => 1, PrintError => 1 });

    my $rs = $schema->resultset('BindType');
    my $id = 0;

    foreach my $type (qw( blob clob a_memo )) {
      foreach my $size (qw( small large )) {
        SKIP: {
          skip 'TEXT columns not cast to MEMO over ODBC', 2
            if $type eq 'clob' && $size eq 'large' && $dsn =~ /:ODBC:/;

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
    }
# test IMAGE update
    lives_ok {
      $rs->search({ id => 0 })->update({ blob => $binstr{small} });
    } 'updated IMAGE to small binstr without dying';

    lives_ok {
      $rs->search({ id => 0 })->update({ blob => $binstr{large} });
    } 'updated IMAGE to large binstr without dying';
  }

# test GUIDs (and the cursor GUID fixup stuff for ADO)

  require Data::GUID;
  $schema->storage->new_guid(sub { Data::GUID->new->as_string });

  local $schema->source('ArtistGUID')->column_info('artistid')->{data_type}
    = 'guid';

  local $schema->source('ArtistGUID')->column_info('a_guid')->{data_type}
    = 'guid';

  $schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { local $^W = 0; $dbh->do("DROP TABLE artist_guid") };
    $dbh->do(<<"SQL");
CREATE TABLE artist_guid (
   artistid GUID NOT NULL,
   name VARCHAR(100),
   rank INT NULL,
   charfield CHAR(10) NULL,
   a_guid GUID,
   primary key(artistid)
)
SQL
  });

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
    'PK GUID round trip (via ->search->next)';

  is $row_from_db->a_guid, $row->a_guid,
    'NON-PK GUID round trip (via ->search->next)';

  $row_from_db = $schema->resultset('ArtistGUID')
    ->find($row->artistid);

  is $row_from_db->artistid, $row->artistid,
    'PK GUID round trip (via ->find)';

  is $row_from_db->a_guid, $row->a_guid,
    'NON-PK GUID round trip (via ->find)';

  ($row_from_db) = $schema->resultset('ArtistGUID')
    ->search({ name => 'mtfnpy' })->all;

  is $row_from_db->artistid, $row->artistid,
    'PK GUID round trip (via ->search->all)';

  is $row_from_db->a_guid, $row->a_guid,
    'NON-PK GUID round trip (via ->search->all)';
}

done_testing;

sub cleanup {
  if (my $storage = eval { $schema->storage }) {
    # cannot drop a table if it has been used, have to reconnect first
    $schema->storage->disconnect;
    local $^W = 0; # for ADO OLE exceptions
    $schema->storage->dbh->do("DROP TABLE $_")
      for qw/artist track cd bindtype_test artist_guid/;
  }
}

# vim:sts=2 sw=2:

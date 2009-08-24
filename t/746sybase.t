use strict;
use warnings;  
no warnings 'uninitialized';

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_SYBASE_${_}" } qw/DSN USER PASS/};

my $TESTS = 37 + 2;

if (not ($dsn && $user)) {
  plan skip_all =>
    'Set $ENV{DBICTEST_SYBASE_DSN}, _USER and _PASS to run this test' .
    "\nWarning: This test drops and creates the tables " .
    "'artist' and 'bindtype_test'";
} else {
  plan tests => $TESTS*2;
}

my @storage_types = (
  'DBI::Sybase',
  'DBI::Sybase::NoBindVars',
);
my $schema;
my $storage_idx = -1;

sub get_schema {
  DBICTest::Schema->connect($dsn, $user, $pass, {
    on_connect_call => [
      [ blob_setup => log_on_update => 1 ], # this is a safer option
    ],
  });
}

for my $storage_type (@storage_types) {
  $storage_idx++;

  unless ($storage_type eq 'DBI::Sybase') { # autodetect
    DBICTest::Schema->storage_type("::$storage_type");
  }

  $schema = get_schema();

  $schema->storage->ensure_connected;

  if ($storage_idx == 0 &&
      $schema->storage->isa('DBIx::Class::Storage::DBI::Sybase::NoBindVars')) {
# no placeholders in this version of Sybase or DBD::Sybase (or using FreeTDS)
      my $tb = Test::More->builder;
      $tb->skip('no placeholders') for 1..$TESTS;
      next;
  }

  isa_ok( $schema->storage, "DBIx::Class::Storage::$storage_type" );

  $schema->storage->_dbh->disconnect;
  lives_ok (sub { $schema->storage->dbh }, 'reconnect works');

  $schema->storage->dbh_do (sub {
      my ($storage, $dbh) = @_;
      eval { $dbh->do("DROP TABLE artist") };
      $dbh->do(<<'SQL');
CREATE TABLE artist (
   artistid INT IDENTITY PRIMARY KEY,
   name VARCHAR(100),
   rank INT DEFAULT 13 NOT NULL,
   charfield CHAR(10) NULL
)
SQL
  });

  my %seen_id;

# so we start unconnected
  $schema->storage->disconnect;

# test primary key handling
  my $new = $schema->resultset('Artist')->create({ name => 'foo' });
  ok($new->artistid > 0, "Auto-PK worked");

  $seen_id{$new->artistid}++;

# check redispatch to storage-specific insert when auto-detected storage
  if ($storage_type eq 'DBI::Sybase') {
    DBICTest::Schema->storage_type('::DBI');
    $schema = get_schema();
  }

  $new = $schema->resultset('Artist')->create({ name => 'Artist 1' });
  is ( $seen_id{$new->artistid}, undef, 'id for Artist 1 is unique' );
  $seen_id{$new->artistid}++;

# inserts happen in a txn, so we make sure it still works inside a txn too
  $schema->txn_begin;

  for (2..6) {
    $new = $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
    is ( $seen_id{$new->artistid}, undef, "id for Artist $_ is unique" );
    $seen_id{$new->artistid}++;
  }

  $schema->txn_commit;

# test simple count
  is ($schema->resultset('Artist')->count, 7, 'count(*) of whole table ok');

# test LIMIT support
  my $it = $schema->resultset('Artist')->search({
    artistid => { '>' => 0 }
  }, {
    rows => 3,
    order_by => 'artistid',
  });

  is( $it->count, 3, "LIMIT count ok" );

  is( $it->next->name, "foo", "iterator->next ok" );
  $it->next;
  is( $it->next->name, "Artist 2", "iterator->next ok" );
  is( $it->next, undef, "next past end of resultset ok" );

# now try with offset
  $it = $schema->resultset('Artist')->search({}, {
    rows => 3,
    offset => 3,
    order_by => 'artistid',
  });

  is( $it->count, 3, "LIMIT with offset count ok" );

  is( $it->next->name, "Artist 3", "iterator->next ok" );
  $it->next;
  is( $it->next->name, "Artist 5", "iterator->next ok" );
  is( $it->next, undef, "next past end of resultset ok" );

# now try a grouped count
  $schema->resultset('Artist')->create({ name => 'Artist 6' })
    for (1..6);

  $it = $schema->resultset('Artist')->search({}, {
    group_by => 'name'
  });

  is( $it->count, 7, 'COUNT of GROUP_BY ok' );

# do an identity insert (which should happen with no txn when using
# placeholders.)
  {
    no warnings 'redefine';

    my @debug_out;
    local $schema->storage->{debug} = 1;
    local $schema->storage->debugobj->{callback} = sub {
      push @debug_out, $_[1];
    };

    my $txn_used = 0;
    my $txn_commit = \&DBIx::Class::Storage::DBI::txn_commit;
    local *DBIx::Class::Storage::DBI::txn_commit = sub {
      $txn_used = 1;
      goto &$txn_commit;
    };

    $schema->resultset('Artist')
      ->create({ artistid => 999, name => 'mtfnpy' });

    ok((grep /IDENTITY_INSERT/i, @debug_out), 'IDENTITY_INSERT');

    SKIP: {
      skip 'not testing lack of txn on IDENTITY_INSERT with NoBindVars', 1
        if $storage_type =~ /NoBindVars/i;

      is $txn_used, 0, 'no txn on insert with IDENTITY_INSERT';
    }
  }

# mostly stolen from the blob stuff Nniuq wrote for t/73oracle.t
  SKIP: {
    skip 'TEXT/IMAGE support does not work with FreeTDS', 12
      if $schema->storage->using_freetds;

    my $dbh = $schema->storage->dbh;
    {
      local $SIG{__WARN__} = sub {};
      eval { $dbh->do('DROP TABLE bindtype_test') };

      $dbh->do(qq[
        CREATE TABLE bindtype_test 
        (
          id    INT   IDENTITY PRIMARY KEY,
          bytea INT   NULL,
          blob  IMAGE NULL,
          clob  TEXT  NULL
        )
      ],{ RaiseError => 1, PrintError => 0 });
    }

    my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
    $binstr{'large'} = $binstr{'small'} x 1024;

    my $maxloblen = length $binstr{'large'};
    
    if (not $schema->storage->using_freetds) {
      $dbh->{'LongReadLen'} = $maxloblen * 2;
    } else {
      $dbh->do("set textsize ".($maxloblen * 2));
    }

    my $rs = $schema->resultset('BindType');
    my $last_id;

    foreach my $type (qw(blob clob)) {
      foreach my $size (qw(small large)) {
        no warnings 'uninitialized';

        my $created = eval { $rs->create( { $type => $binstr{$size} } ) };
        ok(!$@, "inserted $size $type without dying");
        diag $@ if $@;

        $last_id = $created->id if $created;

        my $got = eval {
          $rs->find($last_id)->$type
        };
        diag $@ if $@;
        ok($got eq $binstr{$size}, "verified inserted $size $type");
      }
    }

    # blob insert with explicit PK
    # also a good opportunity to test IDENTITY_INSERT
    {
      local $SIG{__WARN__} = sub {};
      eval { $dbh->do('DROP TABLE bindtype_test') };

      $dbh->do(qq[
        CREATE TABLE bindtype_test 
        (
          id    INT   IDENTITY PRIMARY KEY,
          bytea INT   NULL,
          blob  IMAGE NULL,
          clob  TEXT  NULL
        )
      ],{ RaiseError => 1, PrintError => 0 });
    }
    my $created = eval { $rs->create( { id => 1, blob => $binstr{large} } ) };
    ok(!$@, "inserted large blob without dying with manual PK");
    diag $@ if $@;

    my $got = eval {
      $rs->find(1)->blob
    };
    diag $@ if $@;
    ok($got eq $binstr{large}, "verified inserted large blob with manual PK");

    # try a blob update
    my $new_str = $binstr{large} . 'mtfnpy';

    # check redispatch to storage-specific update when auto-detected storage
    if ($storage_type eq 'DBI::Sybase') {
      DBICTest::Schema->storage_type('::DBI');
      $schema = get_schema();
    }

    eval { $rs->search({ id => 1 })->update({ blob => $new_str }) };
    ok !$@, 'updated blob successfully';
    diag $@ if $@;
    $got = eval {
      $rs->find(1)->blob
    };
    diag $@ if $@;
    ok($got eq $new_str, "verified updated blob");
  }

# test MONEY column support
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

  my $row;
  lives_ok {
    $row = $rs->create({ amount => 100 });
  } 'inserted a money value';

  is eval { $rs->find($row->id)->amount }, 100, 'money value round-trip';

  lives_ok {
    $row->update({ amount => 200 });
  } 'updated a money value';

  is eval { $rs->find($row->id)->amount },
    200, 'updated money value round-trip';

  lives_ok {
    $row->update({ amount => undef });
  } 'updated a money value to NULL';

  my $null_amount = eval { $rs->find($row->id)->amount };
  ok(
    (($null_amount == undef) && (not $@)),
    'updated money value to NULL round-trip'
  );
  diag $@ if $@;
}

# clean up our mess
END {
  if (my $dbh = eval { $schema->storage->_dbh }) {
    eval { $dbh->do("DROP TABLE $_") }
      for qw/artist bindtype_test money_test/;
  }
}

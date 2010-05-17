use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Scope::Guard ();

# tests stolen from 749sybase_asa.t

my ($dsn, $user, $pass)    = @ENV{map { "DBICTEST_FIREBIRD_${_}" }      qw/DSN USER PASS/};
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_FIREBIRD_ODBC_${_}" } qw/DSN USER PASS/};

plan skip_all => <<'EOF' unless $dsn || $dsn2;
Set $ENV{DBICTEST_FIREBIRD_DSN} and/or $ENV{DBICTEST_FIREBIRD_ODBC_DSN},
_USER and _PASS to run these tests.

WARNING: this test creates and drops the tables "artist", "bindtype_test" and
"sequence_test"; the generators "gen_artist_artistid", "pkid1_seq", "pkid2_seq"
and "nonpkid_seq" and the trigger "artist_bi".
EOF

my @info = (
  [ $dsn,  $user,  $pass  ],
  [ $dsn2, $user2, $pass2 ],
);

my $schema;

foreach my $conn_idx (0..$#info) {
  my ($dsn, $user, $pass) = @{ $info[$conn_idx] || [] };

  next unless $dsn;

  $schema = DBICTest::Schema->connect($dsn, $user, $pass, {
    auto_savepoint  => 1,
    quote_char      => q["],
    name_sep        => q[.],
    on_connect_call => 'use_softcommit',
  });
  my $dbh = $schema->storage->dbh;

  my $sg = Scope::Guard->new(\&cleanup);

  eval { $dbh->do(q[DROP TABLE "artist"]) };
  $dbh->do(<<EOF);
  CREATE TABLE "artist" (
    "artistid" INT PRIMARY KEY,
    "name" VARCHAR(255),
    "charfield" CHAR(10),
    "rank" INT DEFAULT 13
  )
EOF
  eval { $dbh->do(q[DROP GENERATOR "gen_artist_artistid"]) };
  $dbh->do('CREATE GENERATOR "gen_artist_artistid"');
  eval { $dbh->do('DROP TRIGGER "artist_bi"') };
  $dbh->do(<<EOF);
  CREATE TRIGGER "artist_bi" FOR "artist"
  ACTIVE BEFORE INSERT POSITION 0
  AS
  BEGIN
   IF (NEW."artistid" IS NULL) THEN
    NEW."artistid" = GEN_ID("gen_artist_artistid",1);
  END
EOF
  eval { $dbh->do('DROP TABLE "sequence_test"') };
  $dbh->do(<<EOF);
  CREATE TABLE "sequence_test" (
    "pkid1" INT NOT NULL,
    "pkid2" INT NOT NULL,
    "nonpkid" INT,
    "name" VARCHAR(255)
  )
EOF
  $dbh->do('ALTER TABLE "sequence_test" ADD CONSTRAINT "sequence_test_constraint" PRIMARY KEY ("pkid1", "pkid2")');
  eval { $dbh->do('DROP GENERATOR "pkid1_seq"') };
  eval { $dbh->do('DROP GENERATOR "pkid2_seq"') };
  eval { $dbh->do('DROP GENERATOR "nonpkid_seq"') };
  $dbh->do('CREATE GENERATOR "pkid1_seq"');
  $dbh->do('CREATE GENERATOR "pkid2_seq"');
  $dbh->do('SET GENERATOR "pkid2_seq" TO 9');
  $dbh->do('CREATE GENERATOR "nonpkid_seq"');
  $dbh->do('SET GENERATOR "nonpkid_seq" TO 19');

  my $ars = $schema->resultset('Artist');
  is ( $ars->count, 0, 'No rows at first' );

# test primary key handling
  my $new = $ars->create({ name => 'foo' });
  ok($new->artistid, "Auto-PK worked");

# test auto increment using generators WITHOUT triggers
  for (1..5) {
      my $st = $schema->resultset('SequenceTest')->create({ name => 'foo' });
      is($st->pkid1, $_, "Firebird Auto-PK without trigger: First primary key");
      is($st->pkid2, $_ + 9, "Firebird Auto-PK without trigger: Second primary key");
      is($st->nonpkid, $_ + 19, "Firebird Auto-PK without trigger: Non-primary key");
  }
  my $st = $schema->resultset('SequenceTest')->create({ name => 'foo', pkid1 => 55 });
  is($st->pkid1, 55, "Firebird Auto-PK without trigger: First primary key set manually");

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

# test explicit key spec
  $new = $ars->create ({ name => 'bar', artistid => 66 });
  is($new->artistid, 66, 'Explicit PK worked');
  $new->discard_changes;
  is($new->artistid, 66, 'Explicit PK assigned');

# row update
  lives_ok {
    $new->update({ name => 'baz' })
  } 'update survived';
  $new->discard_changes;
  is $new->name, 'baz', 'row updated';

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

# test ResultSet UPDATE
  lives_and {
    $ars->search({ name => 'foo' })->update({ rank => 4 });

    is eval { $ars->search({ name => 'foo' })->first->rank }, 4;
  } 'Can update a column';

  my ($updated) = $schema->resultset('Artist')->search({name => 'foo'});
  is eval { $updated->rank }, 4, 'and the update made it to the database';


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
  is( eval { $lim->next->artistid }, 101, "iterator->next ok" );
  is( eval { $lim->next->artistid }, 102, "iterator->next ok" );
  is( $lim->next, undef, "next past end of resultset ok" );

# test nested cursors
  {
    my $rs1 = $ars->search({}, { order_by => { -asc  => 'artistid' }});

    my $rs2 = $ars->search({ artistid => $rs1->next->artistid }, {
      order_by => { -desc => 'artistid' }
    });

    is $rs2->next->artistid, 1, 'nested cursors';
  }

# test empty insert
  lives_and {
    my $row = $ars->create({});
    ok $row->artistid;
  } 'empty insert works';

# test inferring the generator from the trigger source and using it with
# auto_nextval
  {
    local $ars->result_source->column_info('artistid')->{auto_nextval} = 1;

    lives_and {
      my $row = $ars->create({ name => 'introspecting generator' });
      ok $row->artistid;
    } 'inferring generator from trigger source works';
  }

# test blobs (stolen from 73oracle.t)
  eval { $dbh->do('DROP TABLE "bindtype_test"') };
  $dbh->do(q[
  CREATE TABLE "bindtype_test"
  (
    "id"     INT PRIMARY KEY,
    "bytea"  INT,
    "blob"   BLOB,
    "clob"   BLOB SUB_TYPE TEXT
  )
  ]);

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
}

done_testing;

# clean up our mess

sub cleanup {
  my $dbh;
  eval {
    $schema->storage->disconnect; # to avoid object FOO is in use errors
    $dbh = $schema->storage->dbh;
  };
  return unless $dbh;

  eval { $dbh->do('DROP TRIGGER "artist_bi"') };
  diag $@ if $@;

  foreach my $generator (qw/gen_artist_artistid pkid1_seq pkid2_seq
                            nonpkid_seq/) {
    eval { $dbh->do(qq{DROP GENERATOR "$generator"}) };
    diag $@ if $@;
  }

  foreach my $table (qw/artist bindtype_test sequence_test/) {
    eval { $dbh->do(qq[DROP TABLE "$table"]) };
    diag $@ if $@;
  }
}

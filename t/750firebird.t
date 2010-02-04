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

  $schema = DBICTest::Schema->connect($dsn, $user, $pass);
  my $dbh = $schema->storage->dbh;

  my $sg = Scope::Guard->new(\&cleanup);

  eval { $dbh->do("DROP TABLE artist") };
  $dbh->do(<<EOF);
  CREATE TABLE artist (
    artistid INT PRIMARY KEY,
    name VARCHAR(255),
    charfield CHAR(10),
    rank INT DEFAULT 13
  )
EOF
  eval { $dbh->do("DROP GENERATOR gen_artist_artistid") };
  $dbh->do('CREATE GENERATOR gen_artist_artistid');
  eval { $dbh->do("DROP TRIGGER artist_bi") };
  $dbh->do(<<EOF);
  CREATE TRIGGER artist_bi FOR artist
  ACTIVE BEFORE INSERT POSITION 0
  AS
  BEGIN
   IF (NEW.artistid IS NULL) THEN
    NEW.artistid = GEN_ID(gen_artist_artistid,1);
  END
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
    # XXX why does insert_bulk not work here?
    my @foo = $ars->populate (\@pop);
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
  SKIP: {
    eval { $dbh->do('DROP TABLE bindtype_test') };
    $dbh->do(q[
    CREATE TABLE bindtype_test
    (
      id     INT PRIMARY KEY,
      bytea  INT,
      a_blob BLOB,
      a_clob BLOB SUB_TYPE TEXT
    )
    ]);

    last SKIP; # XXX blob ops cause segfaults!

    my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
    $binstr{'large'} = $binstr{'small'} x 1024;

    my $maxloblen = length $binstr{'large'};
    local $dbh->{'LongReadLen'} = $maxloblen;

    my $rs = $schema->resultset('BindType');
    my $id = 0;

    foreach my $type (qw( a_blob a_clob )) {
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

  eval { $dbh->do('DROP TRIGGER artist_bi') };
  diag $@ if $@;

  eval { $dbh->do('DROP GENERATOR gen_artist_artistid') };
  diag $@ if $@;

  foreach my $table (qw/artist bindtype_test/) {
    eval { $dbh->do("DROP TABLE $table") };
    #diag $@ if $@;
  }
}

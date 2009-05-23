use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIx::Class::Storage::DBI::Sybase::DateTime;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_SYBASE_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_SYBASE_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 15;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, {AutoCommit => 1});

$schema->storage->ensure_connected;
isa_ok( $schema->storage, 'DBIx::Class::Storage::DBI::Sybase' );

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { $dbh->do("DROP TABLE artist") };
    eval { $dbh->do("DROP TABLE track") };
    $dbh->do(<<'SQL');
CREATE TABLE artist (
   artistid INT IDENTITY PRIMARY KEY,
   name VARCHAR(100),
   rank INT DEFAULT 13 NOT NULL,
   charfield CHAR(10) NULL
)
SQL

# we only need the DT
    $dbh->do(<<'SQL');
CREATE TABLE track (
   trackid INT IDENTITY PRIMARY KEY,
   cd INT,
   position INT,
   last_updated_on DATETIME,
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

TODO: {
    local $TODO = 'Sybase is very very fucked in the limit department';

    is( $it->count, 3, "LIMIT count ok" );
}

# The iterator still works correctly with rows => 3, even though the sql is
# fucked, very interesting.

is( $it->next->name, "foo", "iterator->next ok" );
$it->next;
is( $it->next->name, "Artist 2", "iterator->next ok" );
is( $it->next, undef, "next past end of resultset ok" );

# Test DateTime inflation

my $dt = DBIx::Class::Storage::DBI::Sybase::DateTime
    ->parse_datetime('2004-08-21T14:36:48.080Z');

my $row;
ok( $row = $schema->resultset('Track')->create({
    last_updated_on => $dt,
    cd => 1,
}));
ok( $row = $schema->resultset('Track')
    ->search({ trackid => $row->trackid }, { select => ['last_updated_on'] })
    ->first
);
is( $row->updated_date, $dt, 'DateTime inflation works' );

# clean up our mess
END {
    if (my $dbh = eval { $schema->storage->_dbh }) {
        $dbh->do('DROP TABLE artist');
        $dbh->do('DROP TABLE track');
    }
}

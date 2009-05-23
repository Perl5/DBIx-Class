use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_SYBASE_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_SYBASE_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

plan tests => 12;

my $schema = DBICTest::Schema->connect($dsn, $user, $pass, {AutoCommit => 1});

$schema->storage->ensure_connected;
isa_ok( $schema->storage, 'DBIx::Class::Storage::DBI::Sybase' );

$schema->storage->dbh_do (sub {
    my ($storage, $dbh) = @_;
    eval { $dbh->do("DROP TABLE artist") };
    $dbh->do(<<'SQL');

CREATE TABLE artist (
   artistid INT IDENTITY NOT NULL,
   name VARCHAR(100),
   rank INT DEFAULT 13 NOT NULL,
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

my $it;

$it = $schema->resultset('Artist')->search( {}, {
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


# clean up our mess
END {
    my $dbh = eval { $schema->storage->_dbh };
    $dbh->do('DROP TABLE artist') if $dbh;
}


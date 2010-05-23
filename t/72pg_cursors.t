#!perl
use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;
use Time::HiRes qw(gettimeofday tv_interval);

my ($dsn, $dbuser, $dbpass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $dbuser);

plan tests => 3;

sub create_test_schema {
    my ($schema)=@_;
    $schema->storage->dbh_do(
        sub {
            my (undef,$dbh)=@_;
            local $dbh->{Warn} = 0;
            $dbh->do(q[
          CREATE TABLE artist
          (
              artistid       serial       NOT NULL   PRIMARY KEY,
              name           varchar(100),
              rank           integer,
              charfield      char(10)
          );
            ],{ RaiseError => 0, PrintError => 0 });
        });
}

sub drop_test_schema {
    my ($schema)=@_;
    $schema->storage->dbh_do(
        sub {
            my (undef,$dbh)=@_;
            local $dbh->{Warn} = 0;
            eval { $dbh->do('DROP TABLE IF EXISTS artist') };
            eval { $dbh->do('DROP SEQUENCE public.artist_artistid_seq') };
        });
}

# copied from 100populate.t

my $schema = DBICTest::Schema->connection($dsn, $dbuser, $dbpass, { AutoCommit => 1 });
drop_test_schema($schema);create_test_schema($schema);

END {
    return unless $schema;
    drop_test_schema($schema);
}

my $start_id = 'populateXaaaaaa';
my $rows=1e4;
my $offset = 3;

$schema->populate('Artist', [ [ qw/artistid name/ ], map { [ ($_ + $offset) => $start_id++ ] } ( 1 .. $rows ) ] );
is (
    $schema->resultset ('Artist')->search ({ name => { -like => 'populateX%' } })->count,
    $rows,
    'populate created correct number of rows with massive AoA bulk insert',
);

{
    my $rs=$schema->resultset('Artist')->search({});
    my $count=0;
    my $t0=[gettimeofday];
    $count++ while $rs->next;
    is($count,$rows,'get all the rows (loop)');
    diag('Time for all(loop): '.tv_interval($t0));
}

{
    my $rs=$schema->resultset('Artist')->search({});
    my $t0=[gettimeofday];
    $rs->first;
    diag('Time for first: '.tv_interval($t0));
}

{
    my $rs=$schema->resultset('Artist')->search({});
    my $t0=[gettimeofday];
    my @rows=$rs->all;
    is(scalar(@rows),$rows,'get all the rows (all)');
    diag('Time for all: '.tv_interval($t0));
}

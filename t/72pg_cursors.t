#!perl
use strict;
use warnings;

use Test::More;
use lib qw(t/lib);
use DBICTest;

my ($dsn, $dbuser, $dbpass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $dbuser);

plan tests => 10;

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

my $schema = DBICTest::Schema->connection($dsn, $dbuser, $dbpass, { AutoCommit => 1, use_pg_cursors => 1 });
drop_test_schema($schema);create_test_schema($schema);

my ($called,$page_size)=(0,0);
my $old_sth_new=\&DBIx::Class::Storage::DBI::Pg::Sth::new;
*DBIx::Class::Storage::DBI::Pg::Sth::new=sub {
    ++$called;$page_size=$_[4];
    goto &$old_sth_new;
};

END {
    return unless $schema;
    drop_test_schema($schema);
}

my $start_id = 'populateXaaaaaa';
my $rows=1e4;
my $offset = 3;

$called=0;
$schema->populate('Artist', [ [ qw/artistid name/ ], map { [ ($_ + $offset) => $start_id++ ] } ( 1 .. $rows ) ] );
is ($called,0,'Pg::Sth not created for insert');
is (
    $schema->resultset ('Artist')->search ({ name => { -like => 'populateX%' } })->count,
    $rows,
    'populate created correct number of rows with massive AoA bulk insert',
);

{
    $called=0;
    my $rs=$schema->resultset('Artist')->search({});
    my $count=0;
    $count++ while $rs->next;
    is($count,$rows,'get all the rows (loop)');
    is($called,1,'Pg::Sth called once per rs');
    is($page_size,$DBIx::Class::Storage::DBI::Pg::DEFAULT_PG_CURSORS_PAGE_SIZE,'default page size used');
}

{
    $called=0;
    my $rs=$schema->resultset('Artist')->search({},{pg_cursors_page_size=>10});
    $rs->first;
    is($called,1,'Pg::Sth called again per rs');
    is($page_size,10,'page size from attrs used');
}

{
    $called=0;
    my $rs=$schema->resultset('Artist')->search({});
    my @rows=$rs->all;
    is(scalar(@rows),$rows,'get all the rows (all)');
    is($called,1,'Pg::Sth called again per rs');
    is($page_size,$DBIx::Class::Storage::DBI::Pg::DEFAULT_PG_CURSORS_PAGE_SIZE,'default page size used again');
}


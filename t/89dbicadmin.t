# vim: filetype=perl
use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;


eval 'require JSON::Any';
plan skip_all => 'Install JSON::Any to run this test' if ($@);

eval 'require Text::CSV_XS';
if ($@) {
    eval 'require Text::CSV_PP';
    plan skip_all => 'Install Text::CSV_XS or Text::CSV_PP to run this test' if ($@);
}

my @json_backends = qw/XS JSON DWIW Syck/;
my $tests_per_run = 5;

plan tests => $tests_per_run * @json_backends;

use JSON::Any;
for my $js (@json_backends) {

    eval {JSON::Any->import ($js) };
    SKIP: {
        skip ("Json module $js is not available, skip testing", $tests_per_run) if $@;

        $ENV{JSON_ANY_ORDER} = $js;
        eval { test_dbicadmin () };
        diag $@ if $@;
    }
}

sub test_dbicadmin {
    my $schema = DBICTest->init_schema( sqlite_use_file => 1 );  # reinit a fresh db for every run

    my $employees = $schema->resultset('Employee');
    my @cmd = ($^X, qw|script/dbicadmin --quiet --schema=DBICTest::Schema --class=Employee --tlibs|, q|--connect=["dbi:SQLite:dbname=t/var/DBIxClass.db","","",{"AutoCommit":1}]|, qw|--force --tlibs|);

    system(@cmd, qw|--op=insert --set={"name":"Matt"}|);
    ok( ($employees->count()==1), 'insert count' );

    my $employee = $employees->find(1);
    ok( ($employee->name() eq 'Matt'), 'insert valid' );

    system(@cmd, qw|--op=update --set={"name":"Trout"}|);
    $employee = $employees->find(1);
    ok( ($employee->name() eq 'Trout'), 'update' );

    system(@cmd, qw|--op=insert --set={"name":"Aran"}|);

    open(my $fh, "-|", @cmd, qw|--op=select --attrs={"order_by":"name"}|) or die $!;
    my $data = do { local $/; <$fh> };
    close($fh);
    ok( ($data=~/Aran.*Trout/s), 'select with attrs' );

    system(@cmd, qw|--op=delete --where={"name":"Trout"}|);
    ok( ($employees->count()==1), 'delete' );
}

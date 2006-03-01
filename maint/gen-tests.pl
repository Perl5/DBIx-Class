#!/usr/bin/perl

die "must be run from DBIx::Class root dir" unless -d 't/run';

gen_tests($_) for qw/BasicRels HelperRels/;

sub gen_tests {
    my $variant = shift;
    my $dir = lc $variant;
    system("rm -f t/$dir/*.t");
    
    foreach my $test (map { m[^t/run/(.+)\.tl$]; $1 } split(/\n/, `ls t/run/*.tl`)) {
        open(my $fh, '>', "t/$dir/${test}.t") or die $!;
        print $fh <<"EOF";
use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::$variant;

require "t/run/${test}.tl";
run_tests(DBICTest->schema);
EOF
    close $fh;
    }
}
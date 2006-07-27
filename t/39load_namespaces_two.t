#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

unshift(@INC, './t/lib');

plan tests => 9;

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces(
        resultsource_namespace => 'RSrc',
        resultset_namespace => 'RSet',
        result_namespace => 'Res'
    );
};
ok(!$@) or diag $@;
like($warnings, qr/load_namespaces found ResultSet class C with no corresponding ResultSource/);
like($warnings, qr/load_namespaces found Result class C with no corresponding ResultSource/);

my $source_a = DBICNSTest->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTest->resultset('A');
isa_ok($rset_a, 'DBICNSTest::RSet::A');
my $resclass_a    = DBICNSTest->resultset('A')->result_class;
is($resclass_a, 'DBICNSTest::Res::A');

my $source_b = DBICNSTest->source('B');
isa_ok($source_b, 'DBIx::Class::ResultSource::Table');
my $rset_b   = DBICNSTest->resultset('B');
isa_ok($rset_b, 'DBIx::Class::ResultSet');
my $resclass_b    = DBICNSTest->resultset('B')->result_class;
is($resclass_b, 'DBICNSTest::RSrc::B');

#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

unshift(@INC, './t/lib');

plan tests => 9;

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTestOther;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces(
        source_namespace => '+DBICNSTest::Src',
        resultset_namespace => '+DBICNSTest::RSet',
        result_namespace => '+DBICNSTest::Res'
    );
};
ok(!$@) or diag $@;
like($warnings, qr/load_namespaces found ResultSet class C with no corresponding source-definition class/);
like($warnings, qr/load_namespaces found Result class C with no corresponding source-definition class/);

my $source_a = DBICNSTestOther->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTestOther->resultset('A');
isa_ok($rset_a, 'DBICNSTest::RSet::A');
my $resclass_a    = DBICNSTestOther->resultset('A')->result_class;
is($resclass_a, 'DBICNSTest::Res::A');

my $source_b = DBICNSTestOther->source('B');
isa_ok($source_b, 'DBIx::Class::ResultSource::Table');
my $rset_b   = DBICNSTestOther->resultset('B');
isa_ok($rset_b, 'DBIx::Class::ResultSet');
my $resclass_b    = DBICNSTestOther->resultset('B')->result_class;
is($resclass_b, 'DBICNSTest::Src::B');

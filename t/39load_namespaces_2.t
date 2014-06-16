use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

plan tests => 6;

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces(
        result_namespace => 'Rslt',
        resultset_namespace => 'RSet',
    );
};
ok(!$@) or diag $@;
like($warnings, qr/load_namespaces found ResultSet class 'DBICNSTest::RSet::C' with no corresponding Result class/);

my $source_a = DBICNSTest->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTest->resultset('A');
isa_ok($rset_a, 'DBICNSTest::RSet::A');

my $source_b = DBICNSTest->source('B');
isa_ok($source_b, 'DBIx::Class::ResultSource::Table');
my $rset_b   = DBICNSTest->resultset('B');
isa_ok($rset_b, 'DBIx::Class::ResultSet');

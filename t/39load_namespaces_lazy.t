use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

plan tests => 9;

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces(lazy_load => 1, default_resultset_class => 'RSBase');
};
ok !$@ or diag $@;
ok !$warnings, 'no warnings';

is int DBICNSTest->sources, 0, 'zero sources loaded';

my $source_b = DBICNSTest->source('R');
isa_ok($source_b, 'DBIx::Class::ResultSource::Table');
my $rset_b   = DBICNSTest->resultset('R');
isa_ok($rset_b, 'DBICNSTest::RSBase');
ok ref $source_b->related_source('a'), 'managed to load related';

my $source_a = DBICNSTest->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTest->resultset('A');
isa_ok($rset_a, 'DBICNSTest::ResultSet::A');


is int DBICNSTest->sources, 3, 'two sources loaded';

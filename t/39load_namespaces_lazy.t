use strict;
use warnings;
use Test::More;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

plan tests => 12;

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces(lazy_load => 1, default_resultset_class => 'RSBase');
};
ok !$@, 'namespace is loaded' or diag $@;
ok !$warnings, 'no warnings';

is_deeply(
  [ sort DBICNSTest->sources ],
  [ qw/ A B D R / ],
 'sources() available'
);

for(DBICNSTest->sources) {
  is ref DBICNSTest->source_registrations->{$_}, 'ARRAY', "$_ is lazy";
}

my $source_r = DBICNSTest->source('R');
isa_ok($source_r, 'DBIx::Class::ResultSource::Table');
my $rset_r   = DBICNSTest->resultset('R');
isa_ok($rset_r, 'DBICNSTest::RSBase');
ok ref $source_r->related_source('a'), 'managed to load related';

my $source_a = DBICNSTest->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTest->resultset('A');
isa_ok($rset_a, 'DBICNSTest::ResultSet::A');

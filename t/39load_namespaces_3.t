use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warn;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

lives_ok (sub {
  warnings_exist ( sub {
      package DBICNSTestOther;
      use base qw/DBIx::Class::Schema/;
      __PACKAGE__->load_namespaces(
          result_namespace => [ '+DBICNSTest::Rslt', '+DBICNSTest::OtherRslt' ],
          resultset_namespace => '+DBICNSTest::RSet',
      );
    },
    qr/load_namespaces found ResultSet class C with no corresponding Result class/,
  );
});

my $source_a = DBICNSTestOther->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTestOther->resultset('A');
isa_ok($rset_a, 'DBICNSTest::RSet::A');

my $source_b = DBICNSTestOther->source('B');
isa_ok($source_b, 'DBIx::Class::ResultSource::Table');
my $rset_b   = DBICNSTestOther->resultset('B');
isa_ok($rset_b, 'DBIx::Class::ResultSet');

my $source_d = DBICNSTestOther->source('D');
isa_ok($source_d, 'DBIx::Class::ResultSource::Table');

done_testing;

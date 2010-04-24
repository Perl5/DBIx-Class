#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Warn;

use lib qw(t/lib);
use DBICTest; # do not remove even though it is not used

warnings_exist (
  sub {
    package DBICNSTest;
    use base qw/DBIx::Class::Schema/;
    __PACKAGE__->load_namespaces;
  },
  [
    qr/load_namespaces found ResultSet class C with no corresponding Result class/,
    qr/load_namespaces found ResultSet class DBICNSTest::ResultSet::D that does not subclass DBIx::Class::ResultSet/,
  ],
  'Found warning about extra ResultSet classes, and incorrectly subclassed ResultSets',
);

my $source_a = DBICNSTest->source('A');
isa_ok($source_a, 'DBIx::Class::ResultSource::Table');
my $rset_a   = DBICNSTest->resultset('A');
isa_ok($rset_a, 'DBICNSTest::ResultSet::A');

my $source_b = DBICNSTest->source('B');
isa_ok($source_b, 'DBIx::Class::ResultSource::Table');
my $rset_b   = DBICNSTest->resultset('B');
isa_ok($rset_b, 'DBIx::Class::ResultSet');

for my $moniker (qw/A B/) {
  my $class = "DBICNSTest::Result::$moniker";
  ok(!defined($class->result_source_instance->source_name), "Source name of $moniker not defined");
}

done_testing;

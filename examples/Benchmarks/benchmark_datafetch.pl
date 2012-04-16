#!/usr/bin/env perl

use strict;
use warnings;

use Benchmark qw/cmpthese/;
use FindBin;
use lib "$FindBin::Bin/../../t/lib";
use lib "$FindBin::Bin/../../lib";
use DBICTest::Schema;
use DBIx::Class::ResultClass::HashRefInflator;  # older dbic didn't load it

printf "Benchmarking DBIC version %s\n", DBIx::Class->VERSION;

my $schema = DBICTest::Schema->connect ('dbi:SQLite::memory:');
$schema->deploy;

my $rs = $schema->resultset ('Artist');
$rs->populate ([ map { { name => "Art_$_"} } (1 .. 10000) ]);

my $dbh = $schema->storage->dbh;
my $sql = sprintf ('SELECT %s FROM %s %s',
  join (',', @{$rs->_resolved_attrs->{select}} ),
  $rs->result_source->name,
  $rs->_resolved_attrs->{alias},
);

my $compdbi = sub {
  my @r = $schema->storage->dbh->selectall_arrayref ('SELECT * FROM ' . ${$rs->as_query}->[0] )
} if $rs->can ('as_query');

cmpthese(-3, {
  Cursor => sub { $rs->reset; my @r = $rs->cursor->all },
  HRI => sub { $rs->reset; my @r = $rs->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' } )->all },
  RowObj => sub { $rs->reset; my @r = $rs->all },
  RawDBI => sub { my @r = $dbh->selectall_arrayref ($sql) },
  $compdbi ? (CompDBI => $compdbi) : (),
});

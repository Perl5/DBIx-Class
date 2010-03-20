#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../t/lib";
use lib "$FindBin::Bin/../lib";
use DBICTest;
use DBIx::Class::ResultClass::HashRefInflator;  # older dbic didn't load it

printf "Benchmarking DBIC version %s\n", DBIx::Class->VERSION;

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset ('Artist');
$rs->populate ([ map { { name => "Art_$_"} } (1 .. 10000) ]);

use Benchmark qw/cmpthese/;

cmpthese(-5, {
  'Cursor' => sub { $rs->reset; my @r = $rs->cursor->all },
  'HRI' => sub { $rs->reset; my @r = $rs->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' } )->all },
  'RowObj' => sub { $rs->reset; my @r = $rs->all },
  'DBI' => sub { my @r = $schema->storage->_get_dbh->selectall_arrayref ('SELECT * FROM ' . ${$rs->as_query}->[0] ) },
});

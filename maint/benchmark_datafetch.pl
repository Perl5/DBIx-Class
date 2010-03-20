#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../t/lib";
use lib "$FindBin::Bin/../lib";
use DBICTest;

my $schema = DBICTest->init_schema();
my $rs = $schema->resultset ('Artist');
$rs->populate ([ map { { name => "Art_$_"} } (1 .. 3000) ]);

use Benchmark qw/cmpthese/;

cmpthese(-1, {
  'Cursor' => sub { $rs->reset; my @r = $rs->cursor->all },
  'HRI' => sub { $rs->reset; my @r = $rs->search ({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' } )->all },
  'RowObj' => sub { $rs->reset; my @r = $rs->all },
});

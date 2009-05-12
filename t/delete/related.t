use Test::More;
use strict;
use warnings;
use lib qw(t/lib);
use DBICTest;

plan tests => 3;

my $schema = DBICTest->init_schema();

my $ars = $schema->resultset('Artist');
my $cdrs = $schema->resultset('CD');

# create some custom entries
$ars->create ({ artistid => 9, name => 'dead man walking' });
$cdrs->populate ([
  [qw/cdid artist title   year/],
  [qw/70   2      delete0 2005/],
  [qw/71   3      delete1 2005/],
  [qw/72   3      delete2 2005/],
  [qw/73   3      delete3 2006/],
  [qw/74   3      delete4 2007/],
  [qw/75   9      delete5 2008/],
]);

my $total_cds = $cdrs->count;

# test that delete_related w/o conditions deletes all related records only
$ars->find (9)->delete_related ('cds');
is ($cdrs->count, $total_cds -= 1, 'related delete ok');

my $a3_cds = $ars->find(3)->cds;

# test that related deletion w/conditions deletes just the matched related records only
$a3_cds->search ({ year => 2005 })->delete;
is ($cdrs->count, $total_cds -= 2, 'related + condition delete ok');

# test that related deletion with limit condition works
$a3_cds->search ({}, { rows => 1})->delete;
is ($cdrs->count, $total_cds -= 1, 'related + limit delete ok');

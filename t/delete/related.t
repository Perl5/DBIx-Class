use Test::More;
use strict;
use warnings;
use lib qw(t/lib);
use DBICTest;

plan tests => 6;

my $schema = DBICTest->init_schema();

my $ars = $schema->resultset('Artist');
my $cdrs = $schema->resultset('CD');

# create some custom entries
$ars->populate ([
  [qw/artistid  name/],
  [qw/71        a1/],
  [qw/72        a2/],
  [qw/73        a3/],
]);
$cdrs->populate ([
  [qw/cdid artist title   year/],
  [qw/70   71     delete0 2005/],
  [qw/71   72     delete1 2005/],
  [qw/72   72     delete2 2005/],
  [qw/73   72     delete3 2006/],
  [qw/74   72     delete4 2007/],
  [qw/75   73     delete5 2008/],
]);

my $total_cds = $cdrs->count;

# test that delete_related w/o conditions deletes all related records only
$ars->search ({name => 'a3' })->search_related ('cds')->delete;
is ($cdrs->count, $total_cds -= 1, 'related delete ok');

my $a2_cds = $ars->search ({ name => 'a2' })->search_related ('cds');

# test that related deletion w/conditions deletes just the matched related records only
$a2_cds->search ({ year => 2005 })->delete;
is ($cdrs->count, $total_cds -= 2, 'related + condition delete ok');

# test that related deletion with limit condition works
$a2_cds->search ({}, { rows => 1})->delete;
is ($cdrs->count, $total_cds -= 1, 'related + limit delete ok');

my $tkfk = $schema->resultset('FourKeys_to_TwoKeys');

my ($fa, $fb) = $tkfk->related_resultset ('fourkeys')->populate ([
  [qw/foo bar hello goodbye sensors/],
  [qw/1   1   1     1       a      /],
  [qw/2   2   2     2       b      /],
]);

# This is already provided by DBICTest
#my ($ta, $tb) = $tkfk->related_resultset ('twokeys')->populate ([
#  [qw/artist  cd /],
#  [qw/1       1  /],
#  [qw/2       2  /],
#]);
my ($ta, $tb) = $schema->resultset ('TwoKeys')
                  ->search ( [ { artist => 1, cd => 1 }, { artist => 2, cd => 2 } ])
                    ->all;

my $tkfk_cnt = $tkfk->count;

my $non_void_ctx = $tkfk->populate ([
  { autopilot => 'a', fourkeys =>  $fa, twokeys => $ta },
  { autopilot => 'b', fourkeys =>  $fb, twokeys => $tb },
  { autopilot => 'x', fourkeys =>  $fa, twokeys => $tb },
  { autopilot => 'y', fourkeys =>  $fb, twokeys => $ta },
]);
is ($tkfk->count, $tkfk_cnt += 4, 'FourKeys_to_TwoKeys populated succesfully');

my $sub_rs = $tkfk->search (
  [ 
    { map { $_ => 1 } qw/artist.artistid cd.cdid fourkeys.foo fourkeys.bar fourkeys.hello fourkeys.goodbye/ },
    { map { $_ => 2 } qw/artist.artistid cd.cdid fourkeys.foo fourkeys.bar fourkeys.hello fourkeys.goodbye/ },
  ],
  {
    join => [ 'fourkeys', { twokeys => [qw/artist cd/] } ],
  },
);

is ($sub_rs->count, 2, 'Only two rows from fourkeys match');
$sub_rs->delete;

is ($tkfk->count, $tkfk_cnt -= 2, 'Only two rows deleted');

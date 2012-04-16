use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd_rs = $schema->resultset('CD')->search ({ artist => { '!=', undef }});

# create some CDs without tracks
$cd_rs->create({ artist => 1, title => 'trackless_foo', year => 2010 });
$cd_rs->create({ artist => 1, title => 'trackless_bar', year => 2010 });

my $tr_count = $schema->resultset('Track')->count;

my $tr_rs = $cd_rs->search_related('tracks');


my @tracks;
while ($tr_rs->next) {
  push @tracks, $_;
}

is (scalar @tracks, $tr_count, 'Iteration is correct');
is ($tr_rs->count, $tr_count, 'Count is correct');
is (scalar ($tr_rs->all), $tr_count, 'All is correct');

done_testing;

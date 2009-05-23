use strict;
use warnings;  

use Test::More;
use Test::Exception;

use lib qw(t/lib);

use DBICTest;
use DBIC::SqlMakerTest;

my $schema = DBICTest->init_schema();

eval "use DBD::SQLite";
plan skip_all => 'needs DBD::SQLite for testing' if $@;
plan tests => 22;

# The tag Blue is assigned to cds 1 2 3 and 5
# The tag Cheesy is assigned to cds 2 4 and 5
#
# This combination should make some interesting group_by's
#
my $rs;
my $in_rs = $schema->resultset('Tag')->search({ tag => [ 'Blue', 'Cheesy' ] });

$rs = $schema->resultset('Tag')->search({ tag => 'Blue' });
is($rs->count, 4, 'Count without DISTINCT');

$rs = $schema->resultset('Tag')->search({ tag => [ 'Blue', 'Cheesy' ] }, { group_by => 'tag' });
is($rs->count, 2, 'Count with single column group_by');

$rs = $schema->resultset('Tag')->search({ tag => [ 'Blue', 'Cheesy' ] }, { group_by => 'cd' });
is($rs->count, 5, 'Count with another single column group_by');

$rs = $schema->resultset('Tag')->search({ tag => 'Blue' }, { group_by => [ qw/tag cd/ ]});
is($rs->count, 4, 'Count with multiple column group_by');

$rs = $schema->resultset('Tag')->search({ tag => 'Blue' }, { distinct => 1 });
is($rs->count, 4, 'Count with single column distinct');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->get_column('tag')->as_query } });
is($rs->count, 7, 'Count with IN subquery');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->get_column('tag')->as_query } }, { group_by => 'tag' });
is($rs->count, 2, 'Count with IN subquery with outside group_by');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->get_column('tag')->as_query } }, { distinct => 1 });
is($rs->count, 7, 'Count with IN subquery with outside distinct');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->get_column('tag')->as_query } }, { distinct => 1, select => 'tag' }), 
is($rs->count, 2, 'Count with IN subquery with outside distinct on a single column');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->search({}, { group_by => 'tag' })->get_column('tag')->as_query } });
is($rs->count, 7, 'Count with IN subquery with single group_by');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->search({}, { group_by => 'cd' })->get_column('tag')->as_query } });
is($rs->count, 7, 'Count with IN subquery with another single group_by');

$rs = $schema->resultset('Tag')->search({ tag => { -in => $in_rs->search({}, { group_by => [ qw/tag cd/ ] })->get_column('tag')->as_query } });
is($rs->count, 7, 'Count with IN subquery with multiple group_by');

$rs = $schema->resultset('Tag')->search({ tag => \"= 'Blue'" });
is($rs->count, 4, 'Count without DISTINCT, using literal SQL');

$rs = $schema->resultset('Tag')->search({ tag => \" IN ('Blue', 'Cheesy')" }, { group_by => 'tag' });
is($rs->count, 2, 'Count with literal SQL and single group_by');

$rs = $schema->resultset('Tag')->search({ tag => \" IN ('Blue', 'Cheesy')" }, { group_by => 'cd' });
is($rs->count, 5, 'Count with literal SQL and another single group_by');

$rs = $schema->resultset('Tag')->search({ tag => \" IN ('Blue', 'Cheesy')" }, { group_by => [ qw/tag cd/ ] });
is($rs->count, 7, 'Count with literal SQL and multiple group_by');

$rs = $schema->resultset('Tag')->search({ tag => 'Blue' }, { '+select' => { max => 'tagid' }, distinct => 1 });
is($rs->count, 4, 'Count with +select aggreggate');

$rs = $schema->resultset('Tag')->search({}, { select => 'length(me.tag)', distinct => 1 });
is($rs->count, 3, 'Count by distinct function result as select literal');

my @warnings;
{
  local $SIG{__WARN__} = sub { push @warnings, shift };
  my $row = $schema->resultset('Tag')->search({}, { select => { distinct => 'tag' } })->first;
}

is(@warnings, 1, 'expecteing warn');

dies_ok(sub { my $row = $schema->resultset('Tag')->search({}, { select => { distinct => [qw/tag cd/] } })->first }, 'expecting to die');
dies_ok(sub { my $count = $schema->resultset('Tag')->search({}, { '+select' => \'tagid AS tag_id', distinct => 1 })->count }, 'expecting to die');
dies_ok(sub { my $count = $schema->resultset('Tag')->search({}, { select => { length => 'tag' }, distinct => 1 })->count }, 'expecting to die');

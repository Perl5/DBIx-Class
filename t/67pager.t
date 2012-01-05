use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Storable qw/dclone/;

my $schema = DBICTest->init_schema();

is ($schema->resultset("CD")->count, 5, 'Initial count sanity check');

my $qcnt;
$schema->storage->debugcb(sub { $qcnt++ });
$schema->storage->debug (1);

my $rs = $schema->resultset("CD");

# first page
$qcnt = 0;
my $it = $rs->search(
    {},
    { order_by => 'title',
      rows => 3,
      page => 1 }
);
my $pager = $it->pager;
is ($qcnt, 0, 'No queries on rs/pager creation');

is ($pager->entries_per_page, 3, 'Pager created with correct entries_per_page');
ok ($pager->current_page(-1), 'Set nonexistent page');
is ($pager->current_page, 1, 'Page set behaves correctly');
ok ($pager->current_page(2), 'Set 2nd page');

is ($qcnt, 0, 'No queries on total_count-independent methods');

is( $it->pager->entries_on_this_page, 2, "entries_on_this_page ok for page 2" );

is ($qcnt, 1, 'Count fired to get pager page entries');

$qcnt = 0;
is ($pager->previous_page, 1, 'Correct previous_page');
is ($pager->next_page, undef, 'No more pages');
is ($qcnt, 0, 'No more counts - amount of entries cached in pager');

is( $it->count, 3, "count on paged rs ok" );
is ($qcnt, 1, 'An $rs->count still fires properly');

is( $it->next->title, "Caterwaulin' Blues", "iterator->next ok" );

$it->next;
$it->next;

is( $it->next, undef, "next past end of page ok" );


# second page, testing with array
my @page2 = $rs->search(
    {},
    { order_by => 'title',
      rows => 3,
      page => 2 }
);

is( $page2[0]->title, "Generic Manufactured Singles", "second page first title ok" );

# page a standard resultset
$it = $rs->search(
  {},
  { order_by => 'title',
    rows => 3 }
);
my $page = $it->page(2);

is( $page->count, 2, "standard resultset paged rs count ok" );

is( $page->next->title, "Generic Manufactured Singles", "second page of standard resultset ok" );


# test software-based limit paging
$it = $rs->search(
  {},
  { order_by => 'title',
    rows => 3,
    page => 2,
    software_limit => 1 }
);
is( $it->pager->entries_on_this_page, 2, "software entries_on_this_page ok" );

is( $it->pager->previous_page, 1, "software previous_page ok" );

is( $it->count, 2, "software count on paged rs ok" );

is( $it->next->title, "Generic Manufactured Singles", "software iterator->next ok" );

# test paging with chained searches
$it = $rs->search(
    {},
    { rows => 2,
      page => 2 }
)->search( undef, { order_by => 'title' } );

is( $it->count, 2, "chained searches paging ok" );

# test page with offset
$it = $rs->search({}, {
    rows => 2,
    page => 2,
    offset => 1,
    order_by => 'cdid'
});

my $row = $rs->search({}, {
    order_by => 'cdid',
    offset => 3,
    rows => 1
})->single;

is($row->cdid, $it->first->cdid, 'page with offset');


# test pager on non-title page behavior
$qcnt = 0;
$it = $rs->search({}, { rows => 3 })->page (2);
ok ($it->pager);
is ($qcnt, 0, 'No count on past-first-page pager instantiation');

is ($it->pager->current_page, 2, 'Page set properby by $rs');
is( $it->pager->total_entries, 5, 'total_entries correct' );

$rs->create ({ artist => 1, title => 'MOAR!', year => 2010 });
is( $it->count, 3, 'Dynamic count on filling up page' );
$rs->create ({ artist => 1, title => 'MOAR!!!', year => 2011 });
is( $it->count, 3, 'Count still correct (does not overflow' );

$qcnt = 0;
is( $it->pager->total_entries, 5, 'total_entries properly cached at old value' );
is ($qcnt, 0, 'No queries');

# test fresh pager with explicit total count assignment
$qcnt = 0;
$pager = $rs->search({}, { rows => 4 })->page (2)->pager;
$pager->total_entries (13);

is ($pager->current_page, 2, 'Correct start page');
is ($pager->next_page, 3, 'One more page');
is ($pager->last_page, 4, 'And one more page');
is ($pager->previous_page, 1, 'One page in front');

is ($qcnt, 0, 'No queries with explicitly sey total count');

# test cached resultsets
my $init_cnt = $rs->count;

$it = $rs->search({}, { rows => 3, cache => 1 })->page(2);
is ($it->count, 3, '3 rows');
is (scalar $it->all, 3, '3 objects');

isa_ok($it->pager,'Data::Page','Get a pager back ok');
is($it->pager->total_entries,7);
is($it->pager->current_page,2);
is($it->pager->entries_on_this_page,3);

$it = $it->page(3);
is ($it->count, 1, 'One row');
is (scalar $it->all, 1, 'One object');

isa_ok($it->pager,'Data::Page','Get a pager back ok');
is($it->pager->total_entries,7);
is($it->pager->current_page,3);
is($it->pager->entries_on_this_page,1);


$it->delete;
is ($rs->count, $init_cnt - 1, 'One row deleted as expected');

is ($it->count, 1, 'One row (cached)');
is (scalar $it->all, 1, 'One object (cached)');

# test fresh rs creation with modified defaults
my $p = sub { $schema->resultset('CD')->page(1)->pager->entries_per_page; };

is($p->(), 10, 'default rows is 10');

$schema->default_resultset_attributes({ rows => 5 });

is($p->(), 5, 'default rows is 5');

# does serialization work (preserve laziness, while preserving state if exits)
$qcnt = 0;
$it = $rs->search(
    {},
    { order_by => 'title',
      rows => 5,
      page => 2 }
);
$pager = $it->pager;
is ($qcnt, 0, 'No queries on rs/pager creation');

$it = do { local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema; dclone ($it) };
is ($qcnt, 0, 'No queries on rs/pager freeze/thaw');

is( $it->pager->entries_on_this_page, 1, "entries_on_this_page ok for page 2" );

is ($qcnt, 1, 'Count fired to get pager page entries');

$rs->create({ title => 'bah', artist => 1, year => 2011 });

$qcnt = 0;
$it = do { local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema; dclone ($it) };
is ($qcnt, 0, 'No queries on rs/pager freeze/thaw');

is( $it->pager->entries_on_this_page, 1, "entries_on_this_page ok for page 2, even though underlying count changed" );

is ($qcnt, 0, 'No count fired on pre-existing total count');

done_testing;

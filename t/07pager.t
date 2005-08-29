use Test::More;

plan tests => 8;

use lib qw(t/lib);

use_ok('DBICTest');

# first page
my $it = DBICTest::CD->search(
    {},
    { order_by => 'title',
      rows => 3,
      page => 1 }
);

is( $it->pager->entries_on_this_page, 3, "entries_on_this_page ok" );

is( $it->pager->next_page, 2, "next_page ok" );

is( $it->count, 3, "count on paged rs ok" );

is( $it->next->title, "Caterwaulin' Blues", "iterator->next ok" );

$it->next;
$it->next;

is( $it->next, undef, "next past end of page ok" );

# second page, testing with array
my @page2 = DBICTest::CD->search( 
    {},
    { order_by => 'title',
      rows => 3,
      page => 2 }
);

is( $page2[0]->title, "Generic Manufactured Singles", "second page first title ok" );

# page a standard resultset
$it = DBICTest::CD->search(
  {},
  { order_by => 'title',
    rows => 3 }
);
my $page = $it->page(2);

is( $page->next->title, "Generic Manufactured Singles", "second page of standard resultset ok" );

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
my $pager = DBICTest::CD->page;

is( $pager->entries_on_this_page, 3, "entries_on_this_page ok" );

is( $pager->next_page, 2, "next_page ok" );

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
$pager = DBICTest::CD->page;

is( $pager->entries_on_this_page, 2, "entries on second page ok" );

is( $page2[0]->title, "Generic Manufactured Singles", "second page first title ok" );

# based on a failing criteria submitted by waswas
# requires SQL::Abstract >= 1.20
$it = DBICTest::CD->search(
    { title => [
        -and => 
            {
                -like => '%bees'
            },
            {
                -not_like => 'Forkful%'
            }
        ]
    },
    { rows => 5 }
);
is( $it->count, 1, "complex abstract count ok" );

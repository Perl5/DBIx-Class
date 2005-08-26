use Test::More;

plan tests => 8;

use lib qw(t/lib);

use_ok('DBICTest');

# first page
my ( $pager, $it ) = DBICTest::CD->page(
    {},
    { order_by => 'title',
      rows => 3,
      page => 1 }
);
      
is( $pager->entries_on_this_page, 3, "entries_on_this_page ok" );

is( $pager->next_page, 2, "next_page ok" );

is( $it->next->title, "Caterwaulin' Blues", "iterator->next ok" );

$it->next;
$it->next;

is( $it->next, undef, "next past end of page ok" );

# second page
( $pager, $it ) = DBICTest::CD->page( 
    {},
    { order_by => 'title',
      rows => 3,
      page => 2 }
);

is( $pager->entries_on_this_page, 2, "entries on second page ok" );

is( $it->next->title, "Generic Manufactured Singles", "second page first title ok" );

# XXX: Should we support disable_sql_paging?
#( $pager, $it ) = DBICTest::CD->page(
#    {},
#    { rows => 2,
#      page => 2,
#      disable_sql_paging => 1 } );
#
#cmp_ok( $pager->total_entries, '==', 5, "disable_sql_paging total_entries ok" );
#
#cmp_ok( $pager->previous_page, '==', 1, "disable_sql_paging previous_page ok" );
#
#is( $it->next->title, "Caterwaulin' Blues", "disable_sql_paging iterator->next ok" );
#
#$it->next;
#
#is( $it->next, undef, "disable_sql_paging next past end of page ok" );

# based on a failing criteria submitted by waswas
# requires SQL::Abstract >= 1.20
( $pager, $it ) = DBICTest::CD->page(
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

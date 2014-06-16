use strict;
use warnings;

use Test::More;

use lib 't/cdbi/testlib';
use DBIC::Test::SQLite;

DBICTest::Schema::CD->load_components(qw/CDBICompat CDBICompat::Pager/);

my $schema = DBICTest->init_schema(compose_connection => 1);

DBICTest::CD->result_source_instance->schema->storage($schema->storage);

my ( $pager, $it ) = DBICTest::CD->page(
    {},
    { order_by => 'title',
      rows => 3,
      page => 1 } );

cmp_ok( $pager->entries_on_this_page, '==', 3, "entries_on_this_page ok" );

cmp_ok( $pager->next_page, '==', 2, "next_page ok" );

is( $it->next->title, "Caterwaulin' Blues", "iterator->next ok" );

$it->next;
$it->next;

is( $it->next, undef, "next past end of page ok" );

( $pager, $it ) = DBICTest::CD->page(
    {},
    { rows => 2,
      page => 2,
      disable_sql_paging => 1 } );

cmp_ok( $pager->total_entries, '==', 5, "disable_sql_paging total_entries ok" );

cmp_ok( $pager->previous_page, '==', 1, "disable_sql_paging previous_page ok" );

is( $it->next->title, "Caterwaulin' Blues", "disable_sql_paging iterator->next ok" );

$it->next;

is( $it->next, undef, "disable_sql_paging next past end of page ok" );

# based on a failing criteria submitted by waswas
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

# cleanup globals so we do not trigger the leaktest
for ( map { DBICTest->schema->class($_) } DBICTest->schema->sources ) {
  $_->class_resolver(undef);
  $_->resultset_instance(undef);
  $_->result_source_instance(undef);
}
{
  no warnings qw/redefine once/;
  *DBICTest::schema = sub {};
}

done_testing;

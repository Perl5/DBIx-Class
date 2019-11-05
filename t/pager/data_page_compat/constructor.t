use warnings;
use strict;

use Test::More;
use Test::Exception;

use DBIx::Class::ResultSet::Pager;

my $page = DBIx::Class::ResultSet::Pager->new(7, 10, 12);
isa_ok($page, 'DBIx::Class::ResultSet::Pager');

is($page->first_page, 1, "Adjusted to first possible page");

$page = DBIx::Class::ResultSet::Pager->new(0, 10, -1);
isa_ok($page, 'DBIx::Class::ResultSet::Pager');

is($page->first_page, 1, "Adjusted to first possible page");

throws_ok {
  my $page = DBIx::Class::ResultSet::Pager->new(12, -1, 1);
  }
  qr/one entry per page/, "Can't have entries-per-page less than 1";

# The new empty constructor means we might be empty, let's check for sensible defaults
$page = DBIx::Class::ResultSet::Pager->new;
is($page->entries_per_page,     10);
is($page->total_entries,        0);
is($page->entries_on_this_page, 0);
is($page->first_page,           1);
is($page->last_page,            1);
is($page->first,                0);
is($page->last,                 0);
is($page->previous_page,        undef);
is($page->current_page,         1);
is($page->next_page,            undef);
is($page->skipped,              0);
my @integers = (0 .. 100);
@integers = $page->splice(\@integers);
my $integers = join ',', @integers;
is($integers, '');

$page->current_page(undef);
is($page->current_page, 1);

$page->current_page(-5);
is($page->current_page, 1);

$page->current_page(5);
is($page->current_page, 1);

is_deeply(
  $page->total_entries(100),
  $page,
  "Set-chaining works on total_entries",
);

is_deeply(
  $page->entries_per_page(20),
  $page,
  "Set-chaining works on entries_per_page",
);

is_deeply(
  $page->current_page(2),
  $page,
  "Set-chaining works on current_page",
);


is($page->first, 21);
$page->current_page(3);
is($page->first, 41);

done_testing;

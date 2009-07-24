use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan tests => 3;

my $schema = DBICTest->init_schema();


my $no_prefetch = $schema->resultset('Track')->search_related(cd =>
  {
    'cd.year' => "2000",
  },
  {
    join => 'tags',
    order_by => 'me.trackid',
    rows => 1,
  }
);

my $use_prefetch = $no_prefetch->search(
  {},
  {
    prefetch => 'tags',
  }
);

lives_ok {
  $use_prefetch->all;
} "M -> 1 -> M with order_by using first rs and limit generates valid SQL";

is($no_prefetch->count, $use_prefetch->count, '$no_prefetch->count == $use_prefetch->count');
is(
  scalar ($no_prefetch->all),
  scalar ($use_prefetch->all),
  "Amount of returned rows is right"
);

use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $rs = $schema->resultset('NoPrimaryKey');

my $row = $rs->create ({ foo => 1, bar => 1, baz => 1 });

lives_ok (sub {
  $row->foo (2);
}, 'Set on pkless object works');

is ($row->foo, 2, 'Column updated in-object');

dies_ok (sub {
  $row->update ({baz => 3});
}, 'update() fails on pk-less object');

is ($row->foo, 2, 'Column not updated by failed update()');

dies_ok (sub {
  $row->delete;
}, 'delete() fails on pk-less object');

done_testing;

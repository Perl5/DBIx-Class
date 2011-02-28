use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema(cursor_class => 'DBICTest::Cursor');

lives_ok {
  is($schema->resultset("Artist")->search(), 3, "Three artists returned");
} 'Custom cursor autoloaded';

done_testing;

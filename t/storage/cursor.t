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

SKIP: {
  eval { require Class::Unload }
    or skip 'component_class reentrancy test requires Class::Unload', 1;

  Class::Unload->unload('DBICTest::Cursor');

  lives_ok {
    is($schema->resultset("Artist")->search(), 3, "Three artists still returned");
  } 'Custom cursor auto re-loaded';
}

done_testing;

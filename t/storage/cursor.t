BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBIx::Class::Optional::Dependencies;
use DBICTest;

my $schema = DBICTest->init_schema(cursor_class => 'DBICTest::Cursor');

lives_ok {
  is($schema->resultset("Artist")->search(), 3, "Three artists returned");
} 'Custom cursor autoloaded';

# test component_class reentrancy
SKIP: {
  DBIx::Class::Optional::Dependencies->skip_without( 'Class::Unload>=0.07' );

  Class::Unload->unload('DBICTest::Cursor');

  lives_ok {
    is($schema->resultset("Artist")->search(), 3, "Three artists still returned");
  } 'Custom cursor auto re-loaded';
}

done_testing;

BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

# things will die if this is set
BEGIN { $ENV{DBIC_ASSERT_NO_ERRONEOUS_METAINSTANCE_USE} = 0 }

use strict;
use warnings;

use Test::More;
use Test::Warn;

use DBICTest;

my $s = DBICTest->init_schema( no_deploy => 1 );


warnings_exist {
  DBICTest::Schema::Artist->add_column("somethingnew");
  $s->unregister_source("Artist");
  $s->register_class( Artist => "DBICTest::Schema::Artist" );
}
  qr/The ResultSource instance you just registered on .+ \Qas 'Artist' seems to have no relation to DBICTest::Schema->source('Artist') which in turn is marked stale/,
  'Expected warning on incomplete re-register of schema-class-level source'
;

done_testing;

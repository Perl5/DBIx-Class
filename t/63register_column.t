BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Exception;

use DBICTest;

lives_ok {
  DBICTest::Schema->load_classes('PunctuatedColumnName')
} 'registered columns with weird names';

done_testing;

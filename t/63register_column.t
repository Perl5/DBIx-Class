use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use DBICTest::Schema;

lives_ok {
  DBICTest::Schema->load_classes('PunctuatedColumnName')
} 'registered columns with weird names';

done_testing;

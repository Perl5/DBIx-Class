use strict;
use warnings;

use Test::More;
use Test::Warn;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

my $cd_rs = $schema->resultset("CD");

warnings_exist( sub {
  my $cd = $cd_rs->new({});
}, qr/Calling \$rs->new usually indicates a mistake/,
'deprecation warning when calling new instead of new_result');

done_testing;

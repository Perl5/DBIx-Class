use strict;
use warnings;
use Test::More;
use Test::Warn;

use lib qw(t/lib);

warnings_like { require DBICTest::Plain }
  [
    qr/compose_connection deprecated as of 0\.08000/,
    qr/\QDBIx::Class::ResultSetProxy is DEPRECATED/,
  ],
  'no unexpected warnings'
;

cmp_ok(DBICTest::Plain->resultset('Test')->count, '>', 0, 'count is valid');

done_testing;
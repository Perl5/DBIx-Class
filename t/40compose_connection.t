use strict;
use warnings;
use Test::More;
use Test::Warn;

use lib qw(t/lib);
use DBICTest;

warnings_exist { DBICTest->init_schema( compose_connection => 1, sqlite_use_file => 1 ) }
  [
    qr/compose_connection deprecated as of 0\.08000/,
    qr/\QDBIx::Class::ResultSetProxy is DEPRECATED/,
  ],
  'got expected deprecation warnings'
;

cmp_ok(DBICTest->resultset('Artist')->count, '>', 0, 'count is valid');

done_testing;

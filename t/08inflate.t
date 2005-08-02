use Test::More;
use DateTime;

plan tests => 4;

use lib qw(t/lib);

use_ok('DBICTest');

# inflation test
my $cd = DBICTest::CD->retrieve(3);
is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->month, 1, 'inflated month ok' );

# deflate test
my $now = DateTime->now;
$cd->year( $now );
$cd->update;

($cd) = DBICTest::CD->search( year => $now->year );
is( $cd->year, $now->year, 'deflate ok' );

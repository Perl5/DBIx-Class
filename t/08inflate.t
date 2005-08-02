use Test::More;

plan tests => 4;

use lib qw(t/lib);

use_ok('DBICTest');

# inflation test
my $cd = DBICTest::CD->retrieve(3);
is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->month, 1, 'inflated month ok' );

# deflate test
$cd->year( 2005 );
$cd->update;

($cd) = DBICTest::CD->search( year => 2005 );
is( $cd->year, 2005, 'deflate ok' );

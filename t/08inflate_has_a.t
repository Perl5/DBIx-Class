use Test::More;

eval { require DateTime };
plan skip_all => "Need DateTime for inflation tests" if $@;

plan tests => 7;

use lib qw(t/lib);

use_ok('DBICTest');

use DBIx::Class::CDBICompat::HasA;

unshift(@DBICTest::ISA, 'DBIx::Class::CDBICompat::HasA');

DBICTest::CD->has_a( 'year', 'DateTime',
      inflate => sub { DateTime->new( year => shift ) },
      deflate => sub { shift->year }
);

# inflation test
my $cd = DBICTest::CD->retrieve(3);

is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->month, 1, 'inflated month ok' );

# deflate test
my $now = DateTime->now;
$cd->year( $now );
$cd->update;

($cd) = DBICTest::CD->search( year => $now->year );
is( $cd->year->year, $now->year, 'deflate ok' );

# re-test using alternate deflate syntax
DBICTest::CD->has_a( 'year', 'DateTime',
      inflate => sub { DateTime->new( year => shift ) },
      deflate => 'year'
);

# inflation test
$cd = DBICTest::CD->retrieve(3);

is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->month, 1, 'inflated month ok' );

# deflate test
$now = DateTime->now;
$cd->year( $now );
$cd->update;

($cd) = DBICTest::CD->search( year => $now->year );
is( $cd->year->year, $now->year, 'deflate ok' );


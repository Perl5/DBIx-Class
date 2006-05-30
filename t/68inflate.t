use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

DBICTest::Schema::CD->add_column('year');
my $schema = DBICTest->init_schema();

eval { require DateTime };
plan skip_all => "Need DateTime for inflation tests" if $@;

plan tests => 3;

DBICTest::Schema::CD->inflate_column( 'year',
    { inflate => sub { DateTime->new( year => shift ) },
      deflate => sub { shift->year } }
);
Class::C3->reinitialize;

# inflation test
my $cd = $schema->resultset("CD")->find(3);

is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->month, 1, 'inflated month ok' );

# deflate test
my $now = DateTime->now;
$cd->year( $now );
$cd->update;

($cd) = $schema->resultset("CD")->search( year => $now->year );
is( $cd->year->year, $now->year, 'deflate ok' );


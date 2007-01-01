use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;

DBICTest::Schema::CD->add_column('year');
my $schema = DBICTest->init_schema();

eval { require DateTime };
plan skip_all => "Need DateTime for inflation tests" if $@;

plan tests => 15;

DBICTest::Schema::CD->inflate_column( 'year',
    { inflate => sub { DateTime->new( year => shift ) },
      deflate => sub { shift->year } }
);
Class::C3->reinitialize;

# inflation test
my $cd = $schema->resultset("CD")->find(3);

is( ref($cd->year), 'DateTime', 'year is a DateTime, ok' );

is( $cd->year->year, 1997, 'inflated year ok' );

is( $cd->year->month, 1, 'inflated month ok' );

eval { $cd->year(\'year +1'); };
ok(!$@, 'updated year using a scalarref');
$cd->update();
$cd->discard_changes();

is( ref($cd->year), 'DateTime', 'year is still a DateTime, ok' );

is( $cd->year->year, 1998, 'updated year, bypassing inflation' );

is( $cd->year->month, 1, 'month is still 1' );  

# get_inflated_column test

is( ref($cd->get_inflated_column('year')), 'DateTime', 'get_inflated_column produces a DateTime');

# deflate test
my $now = DateTime->now;
$cd->year( $now );
$cd->update;

($cd) = $schema->resultset("CD")->search( year => $now->year );
is( $cd->year->year, $now->year, 'deflate ok' );

# set_inflated_column test
eval { $cd->set_inflated_column('year', $now) };
ok(!$@, 'set_inflated_column with DateTime object');
$cd->update;

($cd) = $schema->resultset("CD")->search( year => $now->year );                 
is( $cd->year->year, $now->year, 'deflate ok' );

eval { $cd->set_inflated_column('year', \'year + 1') };
print STDERR "ERROR: $@" if($@);
ok(!$@, 'set_inflated_column to "year + 1"');
$cd->update;
$cd->discard_changes();

($cd) = $schema->resultset("CD")->search( year => $now->year + 1 );                 
is( $cd->year->year, $now->year+1, 'deflate ok' );

# store_inflated_column test
eval { $cd->store_inflated_column('year', $now) };
ok(!$@, 'store_inflated_column with DateTime object');
$cd->update;

is( $cd->year->year, $now->year, 'deflate ok' );

# eval { $cd->store_inflated_column('year', \'year + 1') };
# print STDERR "ERROR: $@" if($@);
# ok(!$@, 'store_inflated_column to "year + 1"');

# is_deeply( $cd->year, \'year + 1', 'deflate ok' );


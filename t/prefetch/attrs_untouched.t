BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use warnings;
use strict;

use Test::More;

use DBICTest;
use DBIx::Class::_Util 'dump_value';

my $schema = DBICTest->init_schema();

plan tests => 3;

# bug in 0.07000 caused attr (join/prefetch) to be modifed by search
# so we check the search & attr arrays are not modified
my $search = { 'artist.name' => 'Caterwauler McCrae' };
my $attr = { prefetch => [ qw/artist liner_notes/ ],
             order_by => 'me.cdid' };
my $search_str = dump_value $search;
my $attr_str = dump_value $attr;

my $rs = $schema->resultset("CD")->search($search, $attr);

is( dump_value $search, $search_str, 'Search hash untouched after search()');
is( dump_value $attr, $attr_str, 'Attribute hash untouched after search()');
cmp_ok($rs + 0, '==', 3, 'Correct number of records returned');
